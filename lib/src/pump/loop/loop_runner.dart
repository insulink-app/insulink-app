import 'package:insulink/src/injection/insulin_on_board.dart';
import 'package:insulink/src/pump/loop/loop_algorithm.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/loop/loop_glucose.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/loop/loop_pod_commands.dart';
import 'package:insulink/src/pump/loop/loop_safety.dart';
import 'package:insulink/src/pump/pod_basal_booking.dart';
import 'package:insulink/src/pump/pod_connection.dart';
import 'package:insulink/src/pump/pod_retry.dart';
import 'package:insulink/src/pump/service/pod_monitor.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

/// Runs one automated cycle: read the sensor, read the pod, decide, program.
///
/// Delivers ONLY as a temporary basal rate, and never as a bolus. That is the
/// structural safety decision the rest of the feature rests on, for two reasons:
///
///  * A temporary rate can be taken back. Five minutes of a rate that turns out
///    to be wrong is a fraction of a unit and the next cycle undoes it. A bolus
///    is in the body the moment it is given and no later decision can retrieve it.
///  * A temporary rate expires by itself. Every cycle programs a rate that lasts
///    [LoopLimits.fuse], so if this runner stops, whatever it programmed last runs
///    out and the pod returns to the user's stored basal schedule with no app
///    involved. The requirement to fall back to basal when the pump cannot be
///    reached is therefore met by the pod's own timer, not by code that would
///    have to still be alive to run.
///
/// The user's basal schedule is left on the pod untouched throughout. It is not
/// what runs while the loop is engaged, since every cycle overrides it, but it is
/// what the pod falls back TO, so it stays the safety net rather than becoming a
/// second thing to keep in step.
class PodLoopRunner {
  PodLoopRunner({
    required this.store,
    required this.readGlucose,
    required this.readMealIob,
    required this.onLog,
    required this.notifyStopped,
    PodConnection? connection,
    this.retry = const PodRetry(),
    this.now = DateTime.now,
  }) : _connection = connection ??
            PodConnection(store: store, lease: PodMonitor.serviceLease);

  /// How often a cycle runs. Matches the interval a G7 delivers on, because a
  /// cycle without a new reading can only repeat the last decision.
  static const Duration cycleInterval = Duration(minutes: 5);

  /// How long the pod may stay unreachable before the automation switches itself
  /// back to the basal schedule.
  ///
  /// Equal to [LoopLimits.fuse]: once the fuse has burnt out the pod is running
  /// the schedule regardless of what this app believes, so staying "engaged" past
  /// that point would only be a claim the pod is not honouring.
  static Duration get disengageAfter => LoopLimits.fuse;

  final PodStore store;

  /// The validated sensor input. Injected rather than read here so the runner has
  /// no dependency on the CGM module and can be exercised against fixed data.
  final Future<LoopGlucose> Function() readGlucose;

  /// Insulin on board from the user's own boluses, which reach the loop as
  /// logged meals. Injected because reading them is a storage call this class
  /// should not own; everything else on board comes from [InsulinOnBoard], the
  /// same answer the bolus calculator uses.
  final Future<double> Function(Duration insulinDuration) readMealIob;

  final void Function(String line) onLog;

  /// Tells the user the automation switched itself off. An automated system that
  /// stops quietly leaves them believing delivery is still being managed, which
  /// is worse than never having started it.
  final Future<void> Function(PodLoopStop cause) notifyStopped;

  /// How a failed connect is repeated. Injectable so tests run without waiting
  /// out the real backoff.
  final PodRetry retry;

  final DateTime Function() now;

  final PodConnection _connection;

  DateTime? _lastCycleAt;
  bool _running = false;

  /// Whether a cycle is due. Checked before the store is re-read, so the
  /// ticks in between cost nothing.
  bool get isCycleDue {
    if (_running) {
      return false;
    }
    final last = _lastCycleAt;
    return last == null || now().difference(last) >= cycleInterval;
  }

  /// Runs a cycle if the automation is on and one is due. Never throws: a cycle
  /// that fails leaves the previous rate to expire on its own, which is the safe
  /// outcome by construction.
  Future<void> tick() async {
    if (!isCycleDue) {
      return;
    }
    _running = true;
    _lastCycleAt = now();
    try {
      // The mode is toggled in the UI isolate and the store's cache is per
      // isolate, so this one only ever sees the switch by re-reading. Without
      // this a user who turned the automation OFF could have one more rate
      // programmed onto their pod afterwards.
      await store.reload();
      if (store.loopMode == PodLoopMode.off) {
        await _cycleOnPaper();
        return;
      }
      await _cycle();
    } catch (error) {
      onLog('loop cycle failed: $error');
      await _considerDisengaging();
    } finally {
      await _closeQuietly();
      _running = false;
    }
  }

  /// Works out what the automation WOULD have done, and writes it down.
  ///
  /// This is what OFF means. The question anyone asks about an automation they
  /// have not switched on is what it would have done, and it can be answered for
  /// free: the decision is made from the status the background watch already
  /// read, so no session is opened, no radio is used and the pod's battery is
  /// untouched. Nothing is ever programmed from here.
  ///
  /// A missing or old cached status simply produces no entry. A hypothetical is
  /// not worth waking the pod for.
  Future<void> _cycleOnPaper() async {
    if (!store.hasPod || !store.isActivated) {
      return;
    }
    final status = store.lastStatus;
    final readAt = store.lastStatusAt;
    if (status == null || readAt == null || _isTooOldToImagineWith(readAt)) {
      return;
    }
    final limits = await LoopLimits.load();
    if (!limits.isUsable) {
      return;
    }
    final glucose = await readGlucose();
    final decision = await _decide(limits, glucose, status);
    await _record(decision, delivered: false);
  }

  /// How old a cached status may be to reason from while switched off. Generous,
  /// because nothing is delivered on the answer.
  bool _isTooOldToImagineWith(DateTime readAt) =>
      now().difference(readAt) > const Duration(minutes: 30);

  Future<void> _cycle() async {
    if (!store.hasPod || !store.isActivated) {
      await _disengage(PodLoopStop.noPod);
      return;
    }
    final limits = await LoopLimits.load();
    if (!limits.isUsable) {
      onLog('loop limits unusable: ${limits.problem}');
      await _record(const LoopDecision.cannotDecide(LoopReason.limitsInvalid),
          delivered: false);
      await _disengage(PodLoopStop.limitsInvalid);
      return;
    }
    final glucose = await readGlucose();
    // Only the connect and the status read are inside the retry. Both leave the
    // pod untouched, so repeating them is free, and getting a suspension onto a
    // pod sooner is worth a few seconds. Everything after this point may change
    // what the pod is doing and runs exactly once.
    final attempt = retry.copyWith(onLog: onLog);
    final commands = await attempt.run('loop connect', _open);
    final status = await attempt.run('loop status', commands.readStatus);
    await store.markSeen(now());
    await PodBasalBooking(store, now: now).book(status);
    final decision = _journalIsAhead
        ? const LoopDecision.cannotDecide(LoopReason.clockUnreliable)
        : await _decide(limits, glucose, status);
    await _apply(commands, decision, status);
    await _stopIfPodIsFinished(status);
  }

  /// Stops the automation when the pod itself has stopped for good.
  ///
  /// A pod in alarm or no longer running needs replacing, and no later cycle can
  /// change that. Left engaged it would report an unavailable pod every five
  /// minutes forever while the user believed delivery was being managed.
  ///
  /// Deliberately narrower than the check that refuses a rate: that one also
  /// refuses while a bolus runs, which passes in a minute or two and is no reason
  /// to end anything.
  Future<void> _stopIfPodIsFinished(PodStatusResponse status) async {
    if (status.lifecycle == PodLifecycleStatus.alarm ||
        !status.lifecycle.isRunning) {
      await _disengage(PodLoopStop.podNotDelivering);
    }
  }

  /// Opens a session, dropping the link if it fails so a retry starts clean.
  Future<LoopPodCommands> _open() async {
    try {
      final session = await _connection.openSession(allowScan: false);
      return LoopPodCommands(store: store, session: session, now: now);
    } catch (error) {
      await _closeQuietly();
      rethrow;
    }
  }

  /// Whether the journal is dated ahead of the clock.
  ///
  /// A clock that moved BACKWARDS puts the recent cycles in the future: daylight
  /// saving ending, a manual change, a network time correction, or simply flying
  /// west. Every window from a cycle to now then measures negative, so the
  /// automation's own insulin bills as nothing and the insulin-on-board it
  /// decides from is understated by however much it has recently given.
  ///
  /// That is the one direction of accounting error that lets the next cycle add
  /// MORE, so it is treated as a reason to decide nothing rather than something
  /// to correct for. The pod goes back to the user's schedule and the automation
  /// waits, which costs at most the hour or the timezone that was skipped.
  bool get _journalIsAhead {
    final cycles = store.loopCycles;
    return cycles.isNotEmpty && cycles.first.at.isAfter(now());
  }

  /// Computes the decision from freshly read inputs.
  ///
  /// The insulin-on-board handed to the safety layer has three parts, and all
  /// three have to be there:
  ///
  ///  * the user's own boluses, which reach the loop as logged meals;
  ///  * what the automation has itself added above the schedule. Leaving this out
  ///    is how an automated system stacks its own doses, each cycle correcting on
  ///    top of corrections it had already given;
  ///  * boluses whose outcome nobody could confirm, which are recorded nowhere
  ///    the user's calculator reads. Here they count as delivered, because a dose
  ///    that may be in the body is one the automation must not add on top of.
  Future<LoopDecision> _decide(
    LoopLimits limits,
    LoopGlucose glucose,
    PodStatusResponse status,
  ) async {
    final at = now();
    final iob = await readMealIob(limits.insulinDuration) +
        InsulinOnBoard(limits.insulinDuration)
            .parts(const [], pod: store, now: at)
            .beyondBoluses;
    final schedule = _scheduledRateAt(at);
    final wanted = LoopAlgorithm(limits).wantedUnitsPerHour(
      glucose: glucose,
      iobUnits: iob,
      scheduledUnitsPerHour: schedule,
    );
    return LoopSafety(limits).decide(
      wantedUnitsPerHour: wanted,
      glucose: glucose,
      iobUnits: iob,
      scheduledUnitsPerHour: schedule,
      status: status,
      automatedUnitsLastHour:
          store.automatedUnitsWithin(const Duration(hours: 1), now: at),
      reservoirUnits: status.reservoirUnits,
    );
  }

  /// Programs the decision, or returns the pod to its schedule when there is
  /// nothing to program.
  Future<void> _apply(
    LoopPodCommands commands,
    LoopDecision decision,
    PodStatusResponse status,
  ) async {
    if (!decision.isActionable) {
      await _revert(commands, status);
      await _record(decision, delivered: false);
      onLog('loop stood down (${decision.reason.name}); pod is on its schedule');
      return;
    }
    if (_userRateHolds(decision)) {
      await _record(decision, delivered: false);
      onLog('loop deferred to the temporary rate the user set');
      return;
    }
    await _program(commands, decision, status);
  }

  /// Whether a temporary rate the USER set is still running and should be left
  /// alone.
  ///
  /// Someone who sets a rate before going running has said what they want, and a
  /// cycle five minutes later quietly putting a correction back would undo it
  /// without ever telling them. So the user's rate stands until it expires.
  ///
  /// A suspension is the exception, and has to be: standing aside there would
  /// mean watching a glucose fall through the threshold because of a rate the
  /// user set an hour ago for a run that has finished. Intent wins over the
  /// automation; it does not win over hypoglycaemia.
  bool _userRateHolds(LoopDecision decision) {
    final running = store.temporaryBasal;
    if (running == null || running.automated || !running.covers(now())) {
      return false;
    }
    return decision.unitsPerHour > 0;
  }

  /// Cancels the running temporary rate, then programs the new one.
  ///
  /// The cancel is inside [LoopPodCommands.programTempBasal], not here: leaving
  /// it to the caller is exactly how the basal-schedule path came to be missing
  /// it. This only reports what the pod said it was delivering. The order is
  /// what makes the failure modes fall the right way round: if the cancel lands
  /// and the program does not, the pod returns to the user's own schedule.
  Future<void> _program(
    LoopPodCommands commands,
    LoopDecision decision,
    PodStatusResponse status,
  ) async {
    try {
      await commands.programTempBasal(
        decision.unitsPerHour,
        running: status.delivery.isTempBasalRunning,
      );
    } on LoopCommandRefused catch (refusal) {
      // Recorded, not swallowed. A refusal is a thing that happened to a dosing
      // decision, and a journal that only holds the cycles which worked cannot
      // be used to explain a stretch where nothing did.
      await _record(decision, delivered: false);
      onLog('loop rate refused by the pod: ${refusal.reason}');
      return;
    }
    await _record(decision, delivered: true);
    onLog('loop set ${decision.unitsPerHour} U/h for '
        '${LoopLimits.fuse.inMinutes} min: '
        '${decision.reason.name}${_boundNote(decision)}');
  }

  /// Puts the pod back on its own schedule by ending any temporary rate.
  Future<void> _revert(
    LoopPodCommands commands,
    PodStatusResponse status,
  ) async {
    if (!status.delivery.isTempBasalRunning) {
      return;
    }
    await commands.cancelTempBasal();
  }

  String _boundNote(LoopDecision decision) {
    final bound = decision.boundBy;
    return bound == null ? '' : ', held by ${bound.name}';
  }

  /// The user's own scheduled rate for the hour [at] falls in, which every
  /// decision is anchored on.
  double _scheduledRateAt(DateTime at) {
    final rates = store.basalRates;
    if (rates == null || rates.length != 24) {
      return 0;
    }
    final rate = rates[at.hour];
    return rate.isFinite && rate > 0 ? rate : 0;
  }

  Future<void> _record(LoopDecision decision, {required bool delivered}) {
    return store.recordLoopCycle(PodLoopCycle(
      at: now(),
      unitsPerHour: decision.unitsPerHour,
      scheduledUnitsPerHour: decision.scheduledUnitsPerHour,
      reason: decision.reason,
      delivered: delivered,
      boundBy: decision.boundBy,
      mgdl: decision.mgdl,
      trendPerMinute: decision.trendPerMinute,
      iobUnits: decision.iobUnits,
    ));
  }

  /// Switches back to the basal schedule when the pod has been out of reach for
  /// longer than the fuse.
  ///
  /// Measured from when the pod was last actually seen rather than from a counter
  /// of failures, so a phone that was asleep through several missed cycles reaches
  /// the same conclusion as one that tried and failed every five minutes.
  Future<void> _considerDisengaging() async {
    final lastSeen = store.lastSeenAt;
    if (lastSeen == null || now().difference(lastSeen) >= disengageAfter) {
      await _disengage(PodLoopStop.podUnreachable);
    }
  }

  Future<void> _disengage(PodLoopStop cause) async {
    if (store.loopMode == PodLoopMode.off) {
      return;
    }
    await store.stopLoop(cause);
    onLog('loop switched back to the basal schedule: ${cause.name}');
    try {
      await notifyStopped(cause);
    } on Exception catch (error) {
      onLog('loop stop notice failed: $error');
    }
  }

  Future<void> _closeQuietly() async {
    try {
      await _connection.close();
    } on Exception catch (error) {
      onLog('loop link close failed: $error');
    }
  }
}
