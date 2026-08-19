import 'package:insulink/src/pump/pod_connection.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_alarm.dart';
import 'package:insulink/src/pump/protocol/pod_alarm_status_response.dart';
import 'package:insulink/src/pump/protocol/pod_control_commands.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/service/pod_alarms.dart';
import 'package:insulink/src/pump/insulin_sync.dart';
import 'package:insulink/src/pump/pod_basal_delivery.dart';
import 'package:insulink/src/pump/pump_sync.dart';

/// Watches the paired pod from the background service, so its warnings arrive
/// with the app closed.
///
/// Hosted inside the existing CGM foreground service rather than a second one.
/// That is not just economy: two things scanning for BLE around the clock wedge
/// Android's scanner (see the G7 reconnect notes), so the pod poll shares the one
/// service and never scans — it connects to the address it already knows.
///
/// [tick] is driven by the service watchdog and splits into two halves on purpose:
///
///  - The **contact-free** checks run on every tick. Expiry and "haven't reached
///    the pod in a while" are computed from stored values, so they keep working
///    exactly when the link does not.
///  - The **poll** runs at most every [pollInterval]. Each poll is a full connect
///    and session handshake, and the pod beeps for itself on the urgent problems,
///    so there is no reason to hammer it.
class PodMonitor {
  PodMonitor({
    required this.store,
    required this.alarms,
    required this.onLog,
    PodConnection? connection,
    this.now = DateTime.now,
  }) : _connection = connection ?? PodConnection(store: store);

  /// How often the pod is actually contacted. The pod's own beeper is the primary
  /// alarm for anything urgent, so this trades promptness for the pod's battery
  /// and the radio.
  static const Duration pollInterval = Duration(minutes: 15);

  /// Failed polls before one scan is permitted. Three, so a pod that is simply out
  /// of range for a while does not start the scanner.
  static const int scanAfterFailures = 3;

  final PodStore store;
  final PodAlarmManager alarms;
  final void Function(String line) onLog;
  final DateTime Function() now;

  final PodConnection _connection;

  /// Consecutive polls that never reached the pod. Reset the moment one does.
  int _failedPolls = 0;

  DateTime? _lastPollAttempt;
  bool _polling = false;

  /// Runs the checks that are due. Never throws: a failed poll is logged and the
  /// contact-free warnings still run, because a pod that cannot be reached is one
  /// of the things worth warning about.
  Future<void> tick() async {
    if (!store.hasPod) {
      return;
    }
    await _runQuietly('expiry check', () => alarms.checkExpiry(store));
    await _runQuietly('reachability check', () => alarms.checkReachable(store));
    if (_isPollDue) {
      await _poll();
    }
  }

  bool get _isPollDue {
    if (_polling) {
      return false;
    }
    final last = _lastPollAttempt;
    return last == null || now().difference(last) >= pollInterval;
  }

  /// Reads the pod once and feeds everything that needs a live status.
  Future<void> _poll() async {
    _polling = true;
    _lastPollAttempt = now();
    final mayScan = _failedPolls >= scanAfterFailures;
    try {
      final session = await _connection.openSession(allowScan: mayScan);
      final status = await _read(session, PodStatusPage.defaultPage);
      if (status is! PodStatusResponse) {
        _failedPolls++;
        onLog('pod answered a status request with $status');
        return;
      }
      await store.markSeen(now());
      // A routine status only says the pod IS alarming, never why. The reason is
      // on the alarm page, so it is fetched in the same session rather than left
      // to the next poll — a user told "your pod stopped" needs to know whether
      // that is an occlusion or an empty reservoir.
      final alarm = status.lifecycle == PodLifecycleStatus.alarm
          ? await _readAlarmReason(session)
          : const PodAlarm(0x00);
      _failedPolls = 0;
      // Closed before the mirror is pushed, because closing is what records where
      // the message-packet counter stands — and the mirror is what a restored app
      // resumes that counter from.
      await _closeQuietly();
      await _consume(status, alarm);
    } catch (error) {
      // Catch-all, so a plugin that throws an `Error` still counts as a failed
      // poll and still lets the scan fallback come round, rather than escaping
      // into the service tick.
      _failedPolls++;
      onLog('pod poll failed (${_failedPolls}x): $error');
    } finally {
      await _closeQuietly();
      _polling = false;
    }
  }

  /// Sends one status request and returns whatever the pod answered.
  Future<PodResponse> _read(PodSession session, PodStatusPage page) async {
    final sequence = (store.commandSequence + 1) & 0x0f;
    final response = await session.run(PodGetStatusCommand(
      uniqueId: store.uniqueId!,
      sequenceNumber: sequence,
      page: page,
    ));
    await store.saveCommandSequence(sequence);
    return response;
  }

  /// Asks the pod why it alarmed. A pod that will not say falls back to an
  /// unspecified fault — still worth reporting, since delivery has stopped either
  /// way.
  Future<PodAlarm> _readAlarmReason(PodSession session) async {
    try {
      final page = await _read(session, PodStatusPage.alarmStatus);
      if (page is PodAlarmStatusResponse) {
        return page.alarm;
      }
    } on Exception catch (error) {
      onLog('pod alarm page unavailable: $error');
    }
    return const PodAlarm(_unspecifiedAlarmCode);
  }

  /// An internal-fault code, used when the pod says it is alarming but will not
  /// say why.
  static const int _unspecifiedAlarmCode = 0x33;

  /// Feeds everything that needs a live status.
  Future<void> _consume(PodStatusResponse status, PodAlarm alarm) async {
    await _runQuietly('alarm check', () => alarms.checkAlarm(alarm));
    await _runQuietly('delivery check', () => alarms.checkDelivering(store, status));
    await _runQuietly('reservoir check', () => alarms.checkReservoir(store, status));
    await _runQuietly('reachability check', () => alarms.checkReachable(store));
    await _runQuietly('basal accounting', () => _recordBasal(status));
    await _runQuietly('backend mirror', () => PumpSync().sync(store, status: status));
    await _runQuietly('insulin push', () => InsulinSync().push(store));
    onLog('pod status: $status, alarm: $alarm');
  }

  Future<void> _runQuietly(String what, Future<void> Function() body) async {
    try {
      await body();
    } on Exception catch (error) {
      onLog('pod $what failed: $error');
    }
  }

  Future<void> _closeQuietly() async {
    try {
      await _connection.close();
    } on Exception catch (error) {
      onLog('pod link close failed: $error');
    }
  }

  /// Books the basal insulin delivered since the last poll.
  ///
  /// This is the signal the forecasting model was missing: boluses reach it as
  /// meal records, but basal is a continuous drip that is often about half a day's
  /// insulin, so insulin-on-board built from boluses alone is built from half the
  /// insulin.
  ///
  /// Booked from the programmed schedule, gated on the pod reporting that it is
  /// actually delivering. A suspended or alarming pod books nothing — which is the
  /// point, because those are exactly the windows where the model would otherwise
  /// assume insulin that never arrived.
  Future<void> _recordBasal(PodStatusResponse status) async {
    final rates = store.basalRates;
    final countedTo = store.basalCountedTo;
    if (rates == null || countedTo == null) {
      return;
    }
    final until = now();
    if (!until.isAfter(countedTo)) {
      return;
    }
    if (!status.delivery.isBasalRunning && !status.delivery.isTempBasalRunning) {
      // Nothing was delivered, but the window is still closed — otherwise the next
      // poll would book this stretch as if the pod had been running through it.
      await store.addBasalDelivery(at: until, units: 0, countedTo: until);
      onLog('pod basal: none delivered (${status.delivery.name})');
      return;
    }
    final temporary = store.temporaryBasal;
    final units = PodBasalDelivery(rates, temporary: temporary)
        .unitsBetween(countedTo, until);
    await store.addBasalDelivery(at: until, units: units, countedTo: until);
    // Retired only once the ledger has billed past its end, so the window that
    // straddles the end is still split at the right rate.
    if (temporary != null && !until.isBefore(temporary.end)) {
      await store.clearTemporaryBasal();
    }
    onLog('pod basal: ${units.toStringAsFixed(3)} U since $countedTo');
  }
}
