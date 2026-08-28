import 'package:insulink/src/pump/loop/loop_glucose.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';

/// The dosing arithmetic, and nothing else.
///
/// What comes out of here is what the maths ALONE would ask for. It is not safe
/// to deliver and this class does not pretend otherwise: it has no notion of the
/// pod, the reservoir, insulin already on board beyond the number handed to it,
/// or any ceiling. [LoopSafety] is what turns a wanted rate into a permitted one,
/// and the two are separate files so that a change to the arithmetic can never
/// quietly remove a limit.
///
/// The model is linear on purpose. It has exactly one glucose-lowering constant,
/// the correction factor the user already tunes for the bolus calculator, so
/// there is no second set of numbers to get wrong. A curve would predict the
/// middle of a bolus better and would need a peak-activity time nobody has
/// entered.
///
/// ponytail: linear, matching [ActiveInsulin]. Ceiling: it treats insulin as
/// acting evenly, so it slightly overstates how fast a fresh dose works and
/// understates a stale one. Upgrade path if that proves too coarse: one
/// exponential curve shared by this and the active-insulin readout, never two.
class LoopAlgorithm {
  const LoopAlgorithm(this.limits);

  final LoopLimits limits;

  /// Where glucose is heading: the trend carried forward, less the drop the
  /// insulin already on board still has to cause.
  ///
  /// The two terms overlap, because a falling trend is partly that same insulin
  /// already working. Subtracting both counts some of it twice and so predicts a
  /// lower glucose than is likely. That bias is kept deliberately: it makes the
  /// loop ask for less insulin, and every uncertainty in this file is resolved
  /// towards asking for less.
  double eventualMgdl({
    required LoopGlucose glucose,
    required double iobUnits,
  }) {
    final projected = glucose.projected(LoopLimits.projection.inMinutes);
    return projected - iobUnits * limits.correctionFactorMgdl;
  }

  /// The rate the arithmetic wants, in U/h, before any limit is applied.
  ///
  /// Anchored on the user's own scheduled rate rather than on zero. The pod's
  /// schedule is suspended while the loop runs, so this rate has to carry the
  /// background insulin as well as the correction; starting from zero would mean
  /// a user whose glucose sits exactly on target receives no basal at all.
  double wantedUnitsPerHour({
    required LoopGlucose glucose,
    required double iobUnits,
    required double scheduledUnitsPerHour,
  }) {
    final eventual = eventualMgdl(glucose: glucose, iobUnits: iobUnits);
    final correctionUnits =
        (eventual - limits.targetMgdl) / limits.correctionFactorMgdl;
    final wanted = scheduledUnitsPerHour + correctionUnits / _fuseHours;
    return wanted.isFinite && wanted > 0 ? wanted : 0;
  }

  /// The correction is spread over the fuse, so the rate is the one that would
  /// deliver it if the cycle were never renewed.
  static double get _fuseHours =>
      LoopLimits.fuse.inMinutes / Duration.minutesPerHour;
}
