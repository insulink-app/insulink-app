import '../../google_health/intraday_pulse_store.dart';

/// How hard the heart worked over a GPS segment, judged against the wearer's
/// own rest. [unknown] when the band left too few samples to tell.
enum HeartEffort { unknown, resting, light, hard }

/// The stored pulse curve around the detection window, so the cardio detector
/// can tell effort from a passive ride and a jog from a brisk walk. Pure: the
/// runner loads the samples, this only reads them.
///
/// The baseline is the 10th percentile of the 24 h before a segment. It
/// includes sleep, so it sits below an awake resting pulse; the thresholds are
/// set with that in mind (sitting in a bus lifts it by about 10 to 20 bpm,
/// cycling by 50 and more, jogging by 70 and more).
class HeartRateEvidence {
  const HeartRateEvidence(this.samples);

  /// No pulse data: every segment reads [HeartEffort.unknown], which leaves the
  /// GPS and activity-recognition rules exactly as they were.
  static const none = HeartRateEvidence([]);

  /// Ascending one-per-minute samples, as [IntradayPulseStore] keeps them.
  final List<PulseSample> samples;

  static const _baselineWindow = Duration(hours: 24);
  static const _minBaselineSamples = 60;

  /// The share of a segment's minutes that must carry a sample to judge it.
  static const _minCoverage = 0.5;
  static const _restingLiftBpm = 20;
  static const _hardLiftBpm = 60;

  /// The effort over `[startMs, endMs]`: the median pulse during it, lifted
  /// above the baseline before it.
  HeartEffort effort(int startMs, int endMs) {
    final during = _bpmBetween(startMs, endMs);
    final minutes = (endMs - startMs) / Duration.millisecondsPerMinute;
    final baseline = _bpmBetween(
      startMs - _baselineWindow.inMilliseconds,
      startMs,
    );
    if (during.length < minutes * _minCoverage ||
        baseline.length < _minBaselineSamples) {
      return HeartEffort.unknown;
    }
    final lift = _percentile(during, 0.5) - _percentile(baseline, 0.1);
    if (lift < _restingLiftBpm) {
      return HeartEffort.resting;
    }
    return lift >= _hardLiftBpm ? HeartEffort.hard : HeartEffort.light;
  }

  List<int> _bpmBetween(int fromMs, int toMs) => [
    for (final sample in samples)
      if (sample.at.millisecondsSinceEpoch >= fromMs &&
          sample.at.millisecondsSinceEpoch <= toMs)
        sample.bpm,
  ];

  int _percentile(List<int> values, double share) {
    final sorted = [...values]..sort();
    return sorted[((sorted.length - 1) * share).round()];
  }
}
