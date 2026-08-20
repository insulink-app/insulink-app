import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:insulink/src/pump/demo_pod.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/pump/pod_connection.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/pump_sync.dart';
import 'package:insulink/src/pump/protocol/pod_basal_command.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_control_commands.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/protocol/pod_stop_delivery_command.dart';
import 'package:insulink/src/pump/protocol/pod_temp_basal_command.dart';
import 'package:insulink/src/pump/pod_basal_delivery.dart';
import 'package:insulink/src/pump/pod_running_bolus.dart';

/// The UI's view of the pod, and the few operations it can start.
///
/// Each operation opens a session, does one thing, and closes it — the pod does
/// not hold a link open, so there is no connection to keep alive between taps.
///
/// What a delivery is allowed to be is decided by [PodDeliveryGuard], on the dose
/// and the pod's own reported state — not by a mode the user can be in.
class PodController extends ChangeNotifier {
  PodController({required this.store})
      : _sequence = store.commandSequence,
        _connection = podConnectionFor(store);

  static const int _fixedNonce = podFixedNonce;

  final PodStore store;
  final PodConnection _connection;

  /// The pod command sequence number, a persisted 4-bit counter.
  ///
  /// Distinct from the message-packet sequence inside a session: that one also
  /// advances for acknowledgements, which are not pod commands. Conflating them
  /// makes the pod see a sequence number it has already run and refuse the
  /// command, so this is loaded from and written back to the store on its own.
  int _sequence;

  PodStatusResponse? _status;
  DateTime? _statusReadAt;
  String? _failure;
  bool _busy = false;

  /// The last status read from the pod, or null if none has been read.
  PodStatusResponse? get status => _status;

  /// When [status] was read. Any decision that depends on the pod's state must
  /// check this rather than trusting the cached value.
  DateTime? get statusReadAt => _statusReadAt;

  /// A standing failure to show, cleared when the next operation starts.
  String? get failure => _failure;

  bool get isBusy => _busy;

  bool get hasPod => store.hasPod;

  /// How old [status] is, or null if nothing has been read.
  Duration? get statusAge {
    final readAt = _statusReadAt;
    return readAt == null ? null : DateTime.now().difference(readAt);
  }

  /// Reads the pod's current state.
  Future<void> refresh() => _withSession('refresh', (session) async {
        _status = await _readStatus(session);
        _statusReadAt = DateTime.now();
      });

  /// Stops every kind of delivery. The path that must work when nothing else
  /// does, so it is not gated and carries no computed dose.
  Future<void> suspendDelivery() =>
      _withSession('suspend', (session) async {
        final response = await session.run(PodStopDeliveryCommand.suspendAll(
          uniqueId: store.uniqueId!,
          sequenceNumber: _nextSequence,
          nonce: _fixedNonce,
        ));
        // Remember that WE stopped it, so the background watch does not report a
        // deliberate suspend as the pod having stopped on its own.
        await store.setSuspendedByUs(true);
        // A suspend-everything cuts a running bolus short as well, so its record
        // has to be closed here too, or the overview keeps counting a dose the
        // pod has stopped delivering.
        await _endRunningBolus();
        _absorb(response);
      });

  /// Puts the pod back on its schedule after a suspend.
  ///
  /// Resuming IS programming the basal schedule: the pod has no separate resume,
  /// and a suspend leaves it holding no schedule to go back to. So the caller
  /// passes the profile it should run, exactly as an activation does.
  ///
  /// Without this a suspended pod could only ever be deactivated, which means
  /// thrown away — a full pod in the bin for the sake of a pause.
  Future<void> resumeDelivery(PodBasalProgram program) =>
      _programBasal('resume delivery', program);

  /// Sends an edited basal profile to a pod that is already running.
  ///
  /// The pod holds its whole schedule itself and runs it unattended, so editing
  /// the profile in the app changes nothing until it is sent. Until then the app
  /// would show one schedule while the pod delivered another.
  Future<void> applyBasalProfile(PodBasalProgram program) =>
      _programBasal('send the basal profile', program);

  /// Programs [program] and records it as the schedule the POD is now running.
  ///
  /// Recording it matters as much as sending it: the ledger that feeds the
  /// forecasting model bills against these rates, so a pod reprogrammed without
  /// updating them would have its insulin booked at the old schedule.
  Future<void> _programBasal(String what, PodBasalProgram program) =>
      _withSession(what, (session) async {
        final response = await session.run(PodProgramBasalCommand(
          uniqueId: store.uniqueId!,
          sequenceNumber: _nextSequence,
          nonce: _fixedNonce,
          program: program,
          now: DateTime.now(),
        ));
        await store.saveBasalRates(hourlyRatesOf(program));
        await store.setSuspendedByUs(false);
        _absorb(response);
      });

  /// One rate per hour, sampled from [program] at the middle of each hour so a
  /// half-hour boundary cannot land on the wrong side of it.
  static List<double> hourlyRatesOf(PodBasalProgram program) {
    final midnight = DateTime(2026);
    return [
      for (var hour = 0; hour < 24; hour++)
        program.rateAt(midnight.add(Duration(hours: hour, minutes: 15))),
    ];
  }

  /// Whether the pod is running a schedule other than [program].
  ///
  /// Answered from the rates the pod was PROGRAMMED with, not from the user's
  /// profile, because that is the only record of what the pod is actually doing.
  bool runsDifferentBasalThan(PodBasalProgram program) {
    final onPod = store.basalRates;
    if (!hasPod || onPod == null) {
      return false;
    }
    final wanted = hourlyRatesOf(program);
    for (var hour = 0; hour < 24; hour++) {
      if ((onPod[hour] - wanted[hour]).abs() > 1e-9) {
        return true;
      }
    }
    return false;
  }

  /// Picks up a pod the activation wizard just paired.
  ///
  /// The wizard writes through the same store, but nothing tells this controller
  /// to look again — so the page it returns to would keep saying there is no pod
  /// until it is rebuilt from scratch.
  Future<void> adoptActivatedPod() async {
    await store.reload();
    notifyListeners();
    await refreshIfStale();
  }

  /// Forgets the stopped-bolus notice once the user has seen it.
  void clearCancelledBolus() {
    _cancelledBolus = null;
    notifyListeners();
  }

  /// Reads the pod when what is on screen is too old to act on.
  ///
  /// The pump page opens on this. Without it the page sits on "not read yet" until
  /// the user asks, which means it cannot say whether the pod is delivering — and
  /// a page that cannot say that has to show the control that STOPS delivery,
  /// even when the pod is in fact already stopped.
  ///
  /// Bounded by the same window the delivery guard uses, so opening the page twice
  /// in a minute costs one session, not two.
  ///
  /// A pod that is paired but not yet ACTIVATED is left alone: it refuses a status
  /// request with an illegal-command-state NAK, because in that state it accepts
  /// only the activation sequence. Asking anyway is noise on a link that has an
  /// activation waiting to finish on it.
  Future<void> refreshIfStale() async {
    if (!hasPod || _busy || !store.isActivated) {
      return;
    }
    final age = statusAge;
    if (age != null && age <= _statusFreshFor) {
      return;
    }
    await refresh();
  }

  /// How long a status stays worth trusting. Matches [PodDeliveryGuard].
  static const Duration _statusFreshFor = Duration(minutes: 2);

  /// The bolus the pod is working through, or null once it has run its course.
  ///
  /// Cleared lazily, on the way past: the record only matters while it is live,
  /// and clearing it on a timer would need a timer running for a pod that is
  /// usually doing nothing.
  PodRunningBolus? get runningBolus {
    final bolus = store.runningBolus;
    if (bolus == null || bolus.isFinished(DateTime.now())) {
      return null;
    }
    return bolus;
  }

  /// Tells listeners a bolus started. Called by [BolusDelivery], which writes the
  /// record through the store rather than through this class.
  void notifyRunningBolusChanged() => notifyListeners();

  /// Stops the bolus in progress and corrects the log to what the pod gave.
  ///
  /// The stop is a targeted one: basal keeps running, because a user cutting a
  /// bolus short is not asking to be taken off insulin entirely.
  ///
  /// The delivered amount is taken from the clock at the moment the stop went
  /// out, floored to a whole pulse. That is off by at most one pulse and errs
  /// towards understating what was given — the recoverable direction, since a
  /// user can always log more, while insulin credited but never received would
  /// suppress a correction they need.
  Future<void> cancelBolus() async {
    if (runningBolus == null) {
      return;
    }
    await _withSession('stop the bolus', (session) async {
      final response = await session.run(PodStopDeliveryCommand(
        uniqueId: store.uniqueId!,
        sequenceNumber: _nextSequence,
        nonce: _fixedNonce,
        target: PodDeliveryTarget.bolus,
      ));
      await _endRunningBolus();
      _absorb(response);
    });
  }

  /// Closes the books on a bolus the pod has just been told to stop.
  ///
  /// Called from every path that stops one, not only from [cancelBolus]: a
  /// suspend-everything and a deactivation both cut a running bolus short too,
  /// and leaving the record behind would keep a progress bar counting insulin
  /// that is no longer flowing.
  ///
  /// Does nothing when no bolus was running, so the callers need no condition.
  Future<void> _endRunningBolus() async {
    final bolus = runningBolus;
    if (bolus == null) {
      await store.clearRunningBolus();
      return;
    }
    final given = bolus.deliveredUnits(DateTime.now());
    await store.amendDelivery(bolus.startedAt, given);
    await store.clearRunningBolus();
    _cancelledBolus = (programmed: bolus.programmedUnits, given: given);
  }

  /// What a stopped bolus actually amounted to, until the next operation clears
  /// it. The user has to be told, because the meal it was logged against still
  /// carries the full dose.
  ({double programmed, double given})? get cancelledBolus => _cancelledBolus;

  ({double programmed, double given})? _cancelledBolus;

  /// Whether the pod last reported itself stopped, so the page can offer the way
  /// back rather than a second stop.
  ///
  /// A pod that has not been read is NOT treated as suspended: with no reading to
  /// go on, the control that stops delivery is the one that has to be there.
  bool get isSuspended => _status?.delivery.isSuspended ?? false;

  /// Ends the pod's life so it can be removed, then forgets it.
  ///
  /// The pod is only forgotten once it reports itself stopped. Dropping the key
  /// while it still delivers would leave insulin running with nothing able to
  /// command it.
  Future<void> deactivatePod() => _withSession('deactivate', (session) async {
        final response = await session.run(PodDeactivateCommand(
          uniqueId: store.uniqueId!,
          sequenceNumber: _nextSequence,
          nonce: _fixedNonce,
        ));
        _absorb(response);
        await _endRunningBolus();
        final stopped = _status?.delivery.isSuspended ?? false;
        if (stopped) {
          await store.forgetPod();
        } else {
          _failure = 'Pod did not confirm it stopped — it was NOT forgotten';
        }
      });

  /// Makes the pod beep now, and re-states its reminder beeps while it is there.
  ///
  /// The only way to ask a pod for a sound on demand. Worth having: it answers
  /// whether the pod is in earshot and whether its beeper still works, which is
  /// exactly what you want to know BEFORE relying on it for an occlusion at three
  /// in the morning.
  ///
  /// Carries no nonce and starts no delivery, so it is safe to press at any time.
  Future<void> playTestBeep() => _withSession('beep', (session) async {
        final beepAtEnd = await NotificationSetting.podBolusBeep.load();
        final response = await session.run(PodProgramBeepsCommand(
          uniqueId: store.uniqueId!,
          sequenceNumber: _nextSequence,
          bolusReminder: PodProgramReminder(atEnd: beepAtEnd),
        ));
        _absorb(response);
      });

  /// Acknowledges the pod's alerts so it stops beeping.
  Future<void> silenceAlerts() => _withSession('silence', (session) async {
        final active = _status?.activeAlerts;
        if (active == null || active.isEmpty) {
          return;
        }
        final response = await session.run(PodSilenceAlertsCommand(
          uniqueId: store.uniqueId!,
          sequenceNumber: _nextSequence,
          nonce: _fixedNonce,
          alerts: active,
        ));
        _absorb(response);
      });

  int get _nextSequence {
    _sequence = (_sequence + 1) & 0x0f;
    return _sequence;
  }

  Future<PodStatusResponse> _readStatus(PodSession session) async {
    final response = await session.run(PodGetStatusCommand(
      uniqueId: store.uniqueId!,
      sequenceNumber: _nextSequence,
    ));
    if (response is PodStatusResponse) {
      return response;
    }
    throw PodResponseException('Pod answered a status request with $response');
  }

  /// Takes a status reply as the new known state, and records a refusal as a
  /// failure rather than letting it pass as success.
  ///
  /// A status also reports `lastProgrammingSequenceNumber`, which is tempting to
  /// adopt but is NOT the same counter: it only moves for delivery programs, so
  /// adopting it after a status or an alert acknowledgement would step this
  /// counter BACKWARDS and reuse a number the pod has already run. The counter is
  /// therefore ours alone, persisted after every operation; a genuine desync is
  /// what the pod's `illegalSecurityCode` refusal is for.
  void _absorb(PodResponse response) {
    if (response is PodStatusResponse) {
      _status = response;
      _statusReadAt = DateTime.now();
      return;
    }
    if (response is PodNakResponse) {
      _failure = 'Pod refused the command: ${response.error.name}';
      return;
    }
    _failure = 'Unexpected pod reply';
  }

  /// Runs [body] against a fresh session, always closing the link.
  ///
  /// Closed before the backend mirror goes out rather than only in the `finally`:
  /// closing is what records where the message-packet counter stands, and the
  /// mirror is what a restored app resumes that counter from. Closing twice is a
  /// no-op, so the `finally` still covers every path that threw.
  ///
  /// A [PodCommandOutcomeUnknown] is reported as exactly that: the command may
  /// have taken effect, so the message tells the user to check the pod rather
  /// than implying nothing happened.
  Future<void> _withSession(
    String what,
    Future<void> Function(PodSession session) body,
  ) async {
    if (_busy) {
      return;
    }
    _busy = true;
    _failure = null;
    _cancelledBolus = null;
    notifyListeners();
    try {
      await _resyncFromStorage();
      final session = await _connection.openSession();
      await body(session);
      await store.saveCommandSequence(_sequence);
      await _connection.close();
      await PumpSync().sync(store, status: _status);
    } on PodCommandOutcomeUnknown catch (error) {
      debugPrint('pod: $what outcome UNKNOWN: ${error.message}');
      _failure = 'The pod may have acted on this — check the pod. ${error.message}';
    } catch (error) {
      // Catch-all, not `on Exception`: a plugin that throws an `Error` would
      // otherwise vanish into an unhandled async error and the page would show
      // nothing at all about why the operation did nothing.
      debugPrint('pod: $what FAILED: $error');
      _failure = 'Could not $what: $error';
    } finally {
      await _connection.close();
      _busy = false;
      notifyListeners();
    }
  }

  /// Re-reads the store and adopts the command counter it holds.
  ///
  /// The store's cache is PER ISOLATE. The background service polls the pod every
  /// quarter of an hour and advances that counter; this isolate would otherwise
  /// keep using the value it read at app start and hand the pod a sequence number
  /// it has already run — which the pod refuses as a duplicate. Reading fresh here
  /// is the same discipline `CgmController` follows for its own store.
  Future<void> _resyncFromStorage() async {
    await store.reload();
    _sequence = store.commandSequence;
  }

  /// Programs a bolus on the pod and returns its answer.
  ///
  /// Unlike the maintenance operations this does NOT swallow failures into
  /// [failure]: the caller has to distinguish "refused" from "we do not know",
  /// because only the first one is safe to treat as "no insulin was given". A
  /// [PodCommandOutcomeUnknown] therefore propagates.
  ///
  /// Reads the pod and delivers in ONE session, with [refuseIf] judging the
  /// status that comes back. Two sessions back to back is what a separate status
  /// read used to cost, and the pod hangs up on the second: it drops a link
  /// opened immediately after the previous one closed. One session is also the
  /// truer check — the state the guard judges IS the state the pod is in when the
  /// dose is programmed, with no window in between for it to change.
  ///
  Future<PodResponse> sendBolus(
    PodBolusAmount amount, {
    required String? Function(PodStatusResponse status) refuseIf,
  }) async {
    final uniqueId = store.uniqueId;
    if (uniqueId == null) {
      throw StateError('No pod is paired');
    }
    _busy = true;
    _failure = null;
    _cancelledBolus = null;
    notifyListeners();
    try {
      await _resyncFromStorage();
      final session = await _connection.openSession();
      final status = await _readStatus(session);
      _absorb(status);
      final refusal = refuseIf(status);
      if (refusal != null) {
        throw PodBolusRefused(refusal);
      }
      // Asked fresh each time rather than held: the toggle lives in secure
      // storage and may have been changed on the panel since this screen opened.
      final beepAtEnd = await NotificationSetting.podBolusBeep.load();
      final response = await session.run(PodProgramBolusCommand(
        uniqueId: uniqueId,
        sequenceNumber: _nextSequence,
        nonce: _fixedNonce,
        amount: amount,
        reminder: PodProgramReminder(atEnd: beepAtEnd),
      ));
      await store.saveCommandSequence(_sequence);
      await _connection.close();
      await PumpSync().sync(store, status: _status);
      _absorb(response);
      return response;
    } finally {
      await _connection.close();
      _busy = false;
      notifyListeners();
    }
  }

  /// Picks up credentials that were just written by a restore and reads the pod.
  ///
  /// The pod may simply be out of range, in which case the read fails but the
  /// credentials stay — discarding the only key to a pod that is still on the body
  /// is the one outcome worth avoiding.
  Future<void> adoptRestoredPod() async {
    _sequence = store.commandSequence;
    notifyListeners();
    await refresh();
  }

  /// Runs a temporary basal rate for a set time.
  ///
  /// The stretch is stored BEFORE the
  /// command goes out, so a confirmation lost in transit leaves the ledger
  /// crediting the temporary rate rather than the schedule — understating insulin
  /// is recoverable, claiming insulin the pod may not have delivered is not.
  Future<void> setTemporaryBasal(PodTempBasalRate rate) =>
      _withSession('set temporary basal', (session) async {
        final started = DateTime.now();
        await store.saveTemporaryBasal(PodTemporaryBasal(
          unitsPerHour: rate.unitsPerHour,
          start: started,
          end: started.add(Duration(minutes: rate.minutes)),
        ));
        final response = await session.run(PodProgramTempBasalCommand(
          uniqueId: store.uniqueId!,
          sequenceNumber: _nextSequence,
          nonce: _fixedNonce,
          rate: rate,
          reminder: const PodProgramReminder(atEnd: true),
        ));
        _absorb(response);
      });

  /// Ends a running temporary basal, returning the pod to its schedule.
  ///
  /// Only ever returns delivery to what the user already programmed, so it asks
  /// for nothing beyond the tap.
  Future<void> cancelTemporaryBasal() =>
      _withSession('cancel temporary basal', (session) async {
        final response = await session.run(PodStopDeliveryCommand(
          uniqueId: store.uniqueId!,
          sequenceNumber: _nextSequence,
          nonce: _fixedNonce,
          target: PodDeliveryTarget.tempBasal,
        ));
        final running = store.temporaryBasal;
        if (running != null) {
          await store.saveTemporaryBasal(running.endedAt(DateTime.now()));
        }
        _absorb(response);
      });

  /// The temporary rate running right now, or null.
  PodTemporaryBasal? get activeTemporaryBasal {
    final temporary = store.temporaryBasal;
    return temporary != null && temporary.covers(DateTime.now())
        ? temporary
        : null;
  }
}

/// Thrown when a guard refused a bolus against the pod's freshly read state.
///
/// Distinct from a failure: nothing went wrong and nothing was sent, so the
/// caller may treat it as "no insulin was given" — which is exactly the
/// distinction a delivery path must never blur.
class PodBolusRefused implements Exception {
  PodBolusRefused(this.reason);

  final String reason;

  @override
  String toString() => 'PodBolusRefused: $reason';
}
