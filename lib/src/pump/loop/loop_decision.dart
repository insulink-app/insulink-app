/// What the loop decided to do with the basal rate this cycle.
enum LoopReason {
  /// Glucose is heading for target; the rate is the user's own schedule.
  holdingSchedule,

  /// Above target, so the rate is above the schedule.
  correcting,

  /// Heading below target, so the rate is below the schedule but not zero.
  easingOff,

  /// Zero rate: glucose is at or under the suspend threshold.
  suspendedLow,

  /// Zero rate: the trend puts glucose under the suspend threshold within the
  /// fuse, even though it is above it now.
  suspendedFalling,

  /// Nothing was decided because the sensor input was unusable.
  noGlucose,

  /// Nothing was decided because the pod could not be commanded.
  podUnavailable,

  /// Nothing was decided because the configured limits do not make sense.
  limitsInvalid,

  /// Nothing was decided because the clock moved backwards and the record of
  /// what the automation has already delivered can no longer be measured.
  clockUnreliable,
}

/// Which ceiling held the rate down, when one did.
///
/// Recorded per cycle so a loop that never corrects can be explained without
/// re-running the arithmetic: the log says which number was in the way.
enum LoopBound {
  /// The configured units-per-hour ceiling.
  maxRate,

  /// The insulin-on-board ceiling.
  maxIob,

  /// The insulin that would still fit between glucose now and the suspend
  /// threshold. The guard that makes severe hypoglycaemia unreachable.
  hypoHeadroom,

  /// The rolling one-hour ceiling on automated insulin.
  hourlyCeiling,

  /// What is left in the reservoir.
  reservoir,
}

/// One cycle's outcome: the rate to run, why, and what held it back.
///
/// Carries its inputs as well as its output because it doubles as the audit
/// record. A rate on its own cannot be checked afterwards; a rate next to the
/// glucose, trend and insulin-on-board it was computed from can.
class LoopDecision {
  const LoopDecision({
    required this.unitsPerHour,
    required this.reason,
    required this.scheduledUnitsPerHour,
    this.boundBy,
    this.mgdl,
    this.trendPerMinute,
    this.iobUnits = 0,
    this.eventualMgdl,
  });

  /// A cycle that could not decide anything. The rate is the schedule, because
  /// the schedule is what the pod falls back to anyway and saying otherwise in
  /// the log would misrepresent what ran.
  const LoopDecision.cannotDecide(this.reason)
    : unitsPerHour = 0,
      scheduledUnitsPerHour = 0,
      boundBy = null,
      mgdl = null,
      trendPerMinute = null,
      iobUnits = 0,
      eventualMgdl = null;

  /// The temporary rate to program, in U/h.
  final double unitsPerHour;

  final LoopReason reason;

  /// The user's own scheduled rate for this hour, which the loop's rate replaces.
  final double scheduledUnitsPerHour;

  final LoopBound? boundBy;

  final int? mgdl;
  final double? trendPerMinute;
  final double iobUnits;

  /// Where glucose was predicted to land, counting the trend and the insulin
  /// already on board.
  final double? eventualMgdl;

  /// Whether this decision can be programmed on the pod at all.
  bool get isActionable => switch (reason) {
    LoopReason.noGlucose ||
    LoopReason.podUnavailable ||
    LoopReason.limitsInvalid ||
    LoopReason.clockUnreliable => false,
    _ => true,
  };

  /// Insulin above the schedule that this rate commits to over [fuse], which is
  /// the only part of it that counts as a dose.
  ///
  /// Scheduled basal is maintenance: it offsets the glucose the liver puts out,
  /// so counting it as insulin on board would have the loop refuse to give the
  /// user their own background insulin. Only the excess is a dose.
  double excessUnitsOver(Duration fuse) {
    final excess = unitsPerHour - scheduledUnitsPerHour;
    if (excess <= 0) {
      return 0;
    }
    return excess * fuse.inMinutes / Duration.minutesPerHour;
  }
}
