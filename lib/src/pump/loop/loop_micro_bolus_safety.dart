import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/loop/loop_glucose.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/loop/loop_safety.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';

/// The only thing allowed to turn missing insulin into a micro bolus.
///
/// Runs AFTER [LoopSafety.decide] and only ever adds to a decision that one
/// already allowed: a cycle that suspended, could not decide or found the pod
/// busy never gets a micro bolus, because those checks have already run.
///
/// A micro bolus cannot be taken back, so it is held to the same ceilings as the
/// rate, applied to units instead of units per hour, plus the user's own:
///
///  * a share of the missing insulin, never all of it, so each cycle leaves the
///    rest for the next one to decide on a fresher reading;
///  * the largest single micro bolus, and the automated insulin per hour;
///  * the hypo headroom with NOTHING spread over the fuse. The rate may count on
///    the next cycle to undo it; a bolus may not, so the whole of it has to fit
///    between glucose now and the suspend threshold.
///
/// Like the rate, every limit only ever lowers the dose, never refuses outright.
class LoopMicroBolusSafety {
  const LoopMicroBolusSafety(this.limits);

  final LoopLimits limits;

  /// [decision] with the micro bolus this cycle may give, or unchanged when it
  /// may give none.
  ///
  /// [correctionUnits] is the missing insulin from [LoopAlgorithm].
  /// [automatedUnitsLastHour] is everything the automation added within the
  /// hour, the rate's excess AND micro boluses, so the hourly setting bounds
  /// the automation as a whole and the two paths cannot add up past it.
  LoopDecision apply(
    LoopDecision decision, {
    required double correctionUnits,
    required LoopGlucose glucose,
    required double iobUnits,
    required double automatedUnitsLastHour,
    required DateTime? lastMicroBolusAt,
    required DateTime now,
    double? reservoirUnits,
    double carbCoveredUnits = 0,
  }) {
    if (!_allowed(decision, glucose, lastMicroBolusAt, now)) {
      return decision;
    }
    final settings = limits.microBolus;
    var units = correctionUnits * settings.shareOfMissing;
    LoopBound? boundBy;
    for (final ceiling in [
      (units: settings.maxUnits, bound: LoopBound.maxMicroBolus),
      (
        units: settings.maxUnitsPerHour - automatedUnitsLastHour,
        bound: LoopBound.microBolusHourly,
      ),
      (
        units: LoopSafety(limits).hypoHeadroomUnits(
          glucose,
          LoopSafety.uncoveredIob(iobUnits, carbCoveredUnits),
        ),
        bound: LoopBound.hypoHeadroom,
      ),
      (units: limits.maxIobUnits - iobUnits, bound: LoopBound.maxIob),
      if (reservoirUnits != null)
        (units: reservoirUnits, bound: LoopBound.reservoir),
    ]) {
      if (ceiling.units < units) {
        units = ceiling.units;
        boundBy = ceiling.bound;
      }
    }
    final snapped = PodBolusAmount.snapToPulse(units + _floatNoise);
    return snapped > 0 ? decision.withMicroBolus(snapped, boundBy) : decision;
  }

  /// Whether this cycle may give a micro bolus at all, before any amount.
  bool _allowed(
    LoopDecision decision,
    LoopGlucose glucose,
    DateTime? lastMicroBolusAt,
    DateTime now,
  ) {
    final settings = limits.microBolus;
    if (!settings.enabled || !decision.isActionable) {
      return false;
    }
    if (decision.unitsPerHour <= 0 || glucose.mgdl < settings.fromMgdl) {
      return false;
    }
    if (settings.onlyRising && glucose.trendPerMinute <= 0) {
      return false;
    }
    if (glucose.wasAtOrBelow(
      LoopLimits.minSuspendBelowMgdl,
      within: settings.pauseAfterLow,
    )) {
      return false;
    }
    return lastMicroBolusAt == null ||
        now.difference(lastMicroBolusAt) >= settings.minInterval - _slack;
  }

  /// Added before snapping down to the pulse grid. Ceilings are differences of
  /// doubles, so a limit of exactly 0.30 U arrives as 0.2999999 and would lose a
  /// whole pulse. A billionth of a unit cannot lift a dose over any limit.
  static const double _floatNoise = 1e-9;

  /// Taken off the interval because a micro bolus is booked a few seconds into
  /// its cycle, while the next cycle starts on the cycle clock. Without it an
  /// interval of five minutes would skip every second cycle.
  static const Duration _slack = Duration(minutes: 1);
}
