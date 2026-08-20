import 'package:insulink/src/pump/pod_connection.dart';
import 'package:insulink/src/pump/pod_link_lease.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_alarm.dart';
import 'package:insulink/src/pump/protocol/pod_alarm_status_response.dart';
import 'package:insulink/src/pump/protocol/pod_control_commands.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/service/pod_alarms.dart';
import 'package:insulink/src/pump/insulin_sync.dart';
import 'package:insulink/src/pump/pod_basal_booking.dart';
import 'package:insulink/src/pump/pod_retry.dart';
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
    this.retry = const PodRetry(),
    this.now = DateTime.now,
  }) : _connection =
            connection ?? PodConnection(store: store, lease: serviceLease);

  /// The link lease both halves of the background service share.
  ///
  /// One owner for the whole isolate, not one per feature: the watch and the
  /// automation run chained on the same tick and must not exclude each other,
  /// while both must exclude the UI. No patience, because the service's work is
  /// periodic and coming back later is free.
  static const PodLinkLease serviceLease =
      PodLinkLease('the background service');

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

  /// How a failed connect is repeated. Injectable so tests can assert on the
  /// poll cadence without waiting out the real backoff.
  final PodRetry retry;

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
    // A pod that is paired but not yet activated answers everything except the
    // activation sequence with an illegal-command-state NAK, and an activation
    // is very likely running on that link right now. Polling it would compete
    // for the radio with the wizard that is trying to finish it.
    if (!store.isActivated) {
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
      // Retried inside the poll as well as between polls. Reading a status
      // changes nothing about the pod, so repeating it is free, and the next
      // poll is a quarter of an hour away — long enough for a warning to be
      // late over a link that would have come up on a second try.
      final session = await retry.copyWith(onLog: onLog).run(
        'poll',
        () => _openAndSettle(mayScan),
      );
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

  /// Opens a session, dropping the link if it fails so the next attempt starts
  /// from nothing rather than inheriting a half-open one.
  Future<PodSession> _openAndSettle(bool mayScan) async {
    try {
      return await _connection.openSession(allowScan: mayScan);
    } catch (error) {
      await _closeQuietly();
      rethrow;
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
  Future<void> _recordBasal(PodStatusResponse status) async {
    final units = await PodBasalBooking(store, now: now).book(status);
    if (units == null) {
      return;
    }
    onLog('pod basal: ${units.toStringAsFixed(3)} U booked');
  }
}
