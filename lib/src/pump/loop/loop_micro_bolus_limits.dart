import 'package:insulink/src/pump/loop/loop_micro_bolus_settings.dart';

/// Everything a micro bolus is bounded by beyond the loop's own ceilings, in one
/// value read fresh each cycle.
///
/// Held by [LoopLimits] rather than read separately, so a cycle decides its rate
/// and its micro bolus against the same snapshot of the settings.
class LoopMicroBolusLimits {
  const LoopMicroBolusLimits({
    required this.enabled,
    required this.onlyRising,
    required this.maxUnits,
    required this.shareOfMissing,
    required this.fromMgdl,
    required this.minInterval,
    required this.maxUnitsPerHour,
    required this.pauseAfterLow,
  });

  /// Micro boluses switched off, which is what a limit set built without them
  /// means.
  static const off = LoopMicroBolusLimits(
    enabled: false,
    onlyRising: true,
    maxUnits: 0,
    shareOfMissing: 0,
    fromMgdl: 0,
    minInterval: Duration.zero,
    maxUnitsPerHour: 0,
    pauseAfterLow: Duration.zero,
  );

  /// Reads the user's settings.
  static Future<LoopMicroBolusLimits> load() async {
    return LoopMicroBolusLimits(
      enabled: await LoopMicroBolusSettings.enabled.load(),
      onlyRising: await LoopMicroBolusSettings.onlyRising.load(),
      maxUnits: await LoopMicroBolusSettings.maxUnits.load() / 10,
      shareOfMissing: await LoopMicroBolusSettings.sharePercent.load() / 100,
      fromMgdl: await LoopMicroBolusSettings.fromMgdl.load(),
      minInterval: Duration(
        minutes: await LoopMicroBolusSettings.everyMinutes.load(),
      ),
      maxUnitsPerHour: (await LoopMicroBolusSettings.maxUnitsPerHour.load())
          .toDouble(),
      pauseAfterLow: Duration(
        minutes: await LoopMicroBolusSettings.pauseAfterLow.load(),
      ),
    );
  }

  final bool enabled;
  final bool onlyRising;

  /// The largest single micro bolus, in units.
  final double maxUnits;

  /// The fraction of the missing insulin one micro bolus may give, 0 to 1.
  final double shareOfMissing;

  final int fromMgdl;
  final Duration minInterval;
  final double maxUnitsPerHour;

  /// How long after a reading at or below the stop threshold no micro bolus is
  /// given.
  final Duration pauseAfterLow;

  /// What is wrong with these limits, or null when nothing is. Only checked
  /// while enabled: a switched-off feature cannot stop the rest of the loop.
  String? get problem {
    if (!enabled) {
      return null;
    }
    if (maxUnits <= 0 || maxUnitsPerHour <= 0) {
      return 'Micro bolus ceilings must be above zero';
    }
    if (shareOfMissing <= 0 || shareOfMissing > 1) {
      return 'Micro bolus share $shareOfMissing is outside 0 to 1';
    }
    return null;
  }
}
