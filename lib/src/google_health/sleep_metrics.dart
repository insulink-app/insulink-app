import 'package:insulink/src/google_health/sleep_targets_state.dart';
import 'google_health_models.dart';

/// The derived quality figures for one night, computed from the stage totals
/// ([SleepStages]) plus the chronological [SleepSegment] timeline. All raw —
/// nothing here is stored; the detail page recomputes it per night. The bar
/// metrics mirror the ones the sleep page shows (time-to-deep, deep sleep,
/// interruptions); [sleepIndex] rolls them into a single 0–100.
class SleepMetrics {
  final int deepMinutes;
  final int interruptionMinutes;

  /// Minutes from falling asleep to the first deep-sleep stretch, or null when
  /// the night never reached deep sleep (or carries no timeline).
  final int? timeToSolidMinutes;

  final int sleepIndex;

  const SleepMetrics({
    required this.deepMinutes,
    required this.interruptionMinutes,
    required this.timeToSolidMinutes,
    required this.sleepIndex,
  });

  /// Whether every figure sits inside its target window. A night without a
  /// time to deep sleep does not count as inside.
  bool meets(SleepTargets targets) {
    final timeToSolid = timeToSolidMinutes;
    return timeToSolid != null &&
        targets.timeToSolid.contains(timeToSolid) &&
        targets.deep.contains(deepMinutes) &&
        targets.interruption.contains(interruptionMinutes);
  }

  factory SleepMetrics.of(SleepStages stages, List<SleepSegment>? timeline) =>
      SleepMetrics(
        deepMinutes: stages.deep,
        interruptionMinutes: stages.awake,
        timeToSolidMinutes: _timeToSolid(timeline),
        sleepIndex: _index(stages),
      );

  /// The asleep stages ({deep, rem, light}) start the clock; the first [deep]
  /// stretch stops it. Null if either boundary is missing.
  static int? _timeToSolid(List<SleepSegment>? timeline) {
    if (timeline == null || timeline.isEmpty) {
      return null;
    }
    final asleepStages = {SleepStage.deep, SleepStage.rem, SleepStage.light};
    final onset = timeline
        .where((segment) => asleepStages.contains(segment.stage))
        .fold<int?>(null, (min, segment) => min ?? segment.startMs);
    final firstDeep = timeline
        .where((segment) => segment.stage == SleepStage.deep)
        .fold<int?>(null, (min, segment) => min ?? segment.startMs);
    if (onset == null || firstDeep == null || firstDeep < onset) {
      return null;
    }
    return (firstDeep - onset) ~/ 60000;
  }

  /// Weighted composite: sleep efficiency, deep- and REM-share against typical
  /// targets, and total sleep against an 8 h reference.
  // ponytail: weights + the 20%/22%/480 min references are a heuristic; tune
  // them here if the index feels off against real nights.
  static int _index(SleepStages stages) {
    final asleep = stages.deep + stages.rem + stages.light;
    if (asleep == 0) {
      return 0;
    }
    final inBed = asleep + stages.restless + stages.awake;
    final efficiency = asleep / inBed;
    final deepScore = _clamp((stages.deep / asleep) / 0.20);
    final remScore = _clamp((stages.rem / asleep) / 0.22);
    final durationScore = _clamp(asleep / 480);
    final score =
        0.40 * efficiency +
        0.25 * deepScore +
        0.20 * remScore +
        0.15 * durationScore;
    return (score * 100).round();
  }

  static double _clamp(double value) => value.clamp(0.0, 1.0);
}
