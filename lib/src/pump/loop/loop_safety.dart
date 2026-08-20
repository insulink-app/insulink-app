import 'package:insulink/src/pump/loop/loop_algorithm.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/loop/loop_glucose.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

/// The only thing allowed to turn a wanted rate into a rate that gets programmed.
///
/// Every automated delivery in the app passes through [decide]. The arithmetic
/// that produced the wanted rate lives in [LoopAlgorithm] and is deliberately
/// ignorant of every limit here, so a change to the dosing model cannot remove a
/// guard by accident. Nothing in this file trusts its caller.
///
/// Two rules shape it, and they differ from the rest of the pump code on purpose:
///
///  * **Clamp downwards, never refuse.** The delivery guard on the user's own
///    bolus refuses rather than trimming, because delivering less than a person
///    asked for is its own dosing error. Nobody asked for this rate. Trimming an
///    automated suggestion is exactly right, and refusing outright would leave a
///    high glucose untreated. Every limit is applied as a minimum, so a limit
///    that fails to bind still leaves all the others in the way.
///  * **Suspending is free, delivering is not.** A zero rate is reachable from
///    every branch and costs nothing to be wrong about. So every uncertainty
///    resolves towards zero.
///
/// The guard that gives the feature its central property is [_hypoHeadroom]: the
/// insulin the loop may add is capped at what still fits between glucose now and
/// the suspend threshold, measured over the whole fuse rather than the cycle. So
/// the case it defends against is not the next five minutes, it is the loop dying
/// immediately after programming and the pod running that rate unattended until
/// it expires.
class LoopSafety {
  const LoopSafety(this.limits);

  final LoopLimits limits;

  /// Used only to record the prediction the decision was made against, never to
  /// obtain a rate. Sharing the one formula keeps the audit log honest: a log
  /// showing a different eventual glucose than the one that drove the decision
  /// would be worse than no log.
  LoopAlgorithm get _algorithm => LoopAlgorithm(limits);

  /// The rate that may actually be programmed, with everything that shaped it.
  ///
  /// [automatedUnitsLastHour] is the insulin the loop itself added above the
  /// schedule within the past hour, and [reservoirUnits] is what the pod says it
  /// has left, or null when it will not say.
  LoopDecision decide({
    required double wantedUnitsPerHour,
    required LoopGlucose glucose,
    required double iobUnits,
    required double scheduledUnitsPerHour,
    required PodStatusResponse status,
    required double automatedUnitsLastHour,
    double? reservoirUnits,
  }) {
    if (!limits.isUsable) {
      return const LoopDecision.cannotDecide(LoopReason.limitsInvalid);
    }
    if (!glucose.isUsable) {
      return const LoopDecision.cannotDecide(LoopReason.noGlucose);
    }
    if (!_podCanDeliver(status)) {
      return const LoopDecision.cannotDecide(LoopReason.podUnavailable);
    }
    final schedule = scheduledUnitsPerHour.isFinite && scheduledUnitsPerHour > 0
        ? scheduledUnitsPerHour
        : 0.0;
    final suspension = _suspensionFor(glucose);
    if (suspension != null) {
      return _at(0, suspension, glucose, iobUnits, schedule, null);
    }
    final ceilings = _ceilings(
      glucose: glucose,
      iobUnits: iobUnits,
      schedule: schedule,
      automatedUnitsLastHour: automatedUnitsLastHour,
      reservoirUnits: reservoirUnits,
    );
    var rate = wantedUnitsPerHour.isFinite && wantedUnitsPerHour > 0
        ? wantedUnitsPerHour
        : 0.0;
    LoopBound? boundBy;
    for (final ceiling in ceilings) {
      if (ceiling.unitsPerHour < rate) {
        rate = ceiling.unitsPerHour;
        boundBy = ceiling.bound;
      }
    }
    final snapped = snapToPodGrid(rate);
    return _at(snapped, _reasonFor(snapped, schedule), glucose, iobUnits,
        schedule, boundBy);
  }

  /// The pod meters basal in 0.05 U/h steps.
  ///
  /// Rounded DOWN rather than to nearest, so landing on the grid can never lift
  /// a rate back above a limit that had just brought it under one.
  static double snapToPodGrid(double unitsPerHour) {
    if (!unitsPerHour.isFinite || unitsPerHour <= 0) {
      return 0;
    }
    return (unitsPerHour / _gridStep).floor() * _gridStep;
  }

  static const double _gridStep = 0.05;

  static double get _fuseHours =>
      LoopLimits.fuse.inMinutes / Duration.minutesPerHour;

  bool _podCanDeliver(PodStatusResponse status) {
    if (status.lifecycle == PodLifecycleStatus.alarm) {
      return false;
    }
    if (!status.lifecycle.isRunning) {
      return false;
    }
    return !status.delivery.isBolusing;
  }

  /// Whether glucose alone says to stop, regardless of what the arithmetic asked
  /// for. Checked before any ceiling, because a suspend is not a clamped rate,
  /// it is a different decision.
  LoopReason? _suspensionFor(LoopGlucose glucose) {
    if (glucose.mgdl <= limits.suspendBelowMgdl) {
      return LoopReason.suspendedLow;
    }
    if (glucose.projected(LoopLimits.fuse.inMinutes) <
        limits.suspendBelowMgdl) {
      return LoopReason.suspendedFalling;
    }
    return null;
  }

  /// Every ceiling that applies, each already expressed as a rate.
  List<({double unitsPerHour, LoopBound bound})> _ceilings({
    required LoopGlucose glucose,
    required double iobUnits,
    required double schedule,
    required double automatedUnitsLastHour,
    double? reservoirUnits,
  }) {
    return [
      (unitsPerHour: limits.maxUnitsPerHour, bound: LoopBound.maxRate),
      (
        unitsPerHour: schedule + _hypoHeadroom(glucose, iobUnits),
        bound: LoopBound.hypoHeadroom,
      ),
      (
        unitsPerHour: schedule + _excessRateFor(limits.maxIobUnits - iobUnits),
        bound: LoopBound.maxIob,
      ),
      (
        unitsPerHour: schedule +
            _excessRateFor(limits.maxUnitsPerHour - automatedUnitsLastHour),
        bound: LoopBound.hourlyCeiling,
      ),
      if (reservoirUnits != null)
        (
          unitsPerHour: reservoirUnits / _fuseHours,
          bound: LoopBound.reservoir,
        ),
    ];
  }

  /// The extra insulin per hour that still fits between glucose and the suspend
  /// threshold, once the insulin already on board is subtracted.
  ///
  /// Measured from the LOWER of glucose now and where the trend puts it at the
  /// end of the fuse, so a falling glucose shrinks the allowance before it has
  /// actually fallen.
  ///
  /// Scheduled basal is excluded from this budget. It is maintenance insulin
  /// offsetting the glucose the liver releases, so charging it against the hypo
  /// allowance would have the loop withhold the user's own background insulin
  /// and let them run high for the sake of a hypo that the schedule alone does
  /// not cause.
  double _hypoHeadroom(LoopGlucose glucose, double iobUnits) {
    final projected = glucose.projected(LoopLimits.fuse.inMinutes);
    final reference =
        projected < glucose.mgdl ? projected : glucose.mgdl.toDouble();
    final headroomMgdl = reference - limits.suspendBelowMgdl;
    if (headroomMgdl <= 0) {
      return 0;
    }
    final affordableUnits = headroomMgdl / limits.correctionFactorMgdl;
    return _excessRateFor(affordableUnits - iobUnits);
  }

  /// Turns a budget of extra units into the rate that would deliver exactly that
  /// budget over the fuse. A spent or negative budget allows no extra rate.
  double _excessRateFor(double budgetUnits) {
    if (!budgetUnits.isFinite || budgetUnits <= 0) {
      return 0;
    }
    return budgetUnits / _fuseHours;
  }

  /// A zero rate reached HERE is not a suspend: glucose already cleared both
  /// suspension checks, so it means a ceiling took the rate down or the user's
  /// own schedule is zero for this hour. Calling that "suspended because low"
  /// would put a reason in the log that the numbers do not support.
  LoopReason _reasonFor(double rate, double schedule) {
    if (rate > schedule + _gridStep / 2) {
      return LoopReason.correcting;
    }
    if (rate < schedule - _gridStep / 2) {
      return LoopReason.easingOff;
    }
    return LoopReason.holdingSchedule;
  }

  LoopDecision _at(
    double rate,
    LoopReason reason,
    LoopGlucose glucose,
    double iobUnits,
    double schedule,
    LoopBound? boundBy,
  ) {
    return LoopDecision(
      unitsPerHour: rate,
      reason: reason,
      scheduledUnitsPerHour: schedule,
      boundBy: boundBy,
      mgdl: glucose.mgdl,
      trendPerMinute: glucose.trendPerMinute,
      iobUnits: iobUnits,
      eventualMgdl:
          _algorithm.eventualMgdl(glucose: glucose, iobUnits: iobUnits),
    );
  }
}
