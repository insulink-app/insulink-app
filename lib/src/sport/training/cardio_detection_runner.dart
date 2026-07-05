import '../sport_store.dart';
import 'cardio_detector.dart';
import 'cardio_models.dart';

/// Scans the background GPS + activity logs for finished endurance trainings and
/// adds new ones to the pending list (awaiting the user's confirm/reject),
/// invoking [onDetected] for each so the caller can raise a notification. Runs in
/// the foreground-service isolate off the watchdog tick.
class CardioDetectionRunner {
  final SportStore _store;

  CardioDetectionRunner([this._store = const SportStore()]);

  /// A segment whose last point is closer to now than this may still be an
  /// ongoing ride, so it is left for a later tick to finalise in full.
  static const _tail = Duration(minutes: 5);

  /// Diagnostic counts so the caller can log where the pipeline stands (are GPS
  /// points even being recorded? did anything qualify?).
  Future<({int logPoints, int consideredPoints, int detected})> run(
    Future<void> Function(CardioTraining) onDetected,
  ) async {
    final log = await _store.loadLocationLog();
    final watermark = await _store.loadDetectWatermark() ?? 0;
    final result = selectDetections(
      log,
      await _store.loadActivityLog(),
      watermark,
      DateTime.now(),
    );
    if (result.detected.isNotEmpty) {
      await _store.saveDetectWatermark(result.watermark);
      await _addPending(result.detected, onDetected);
    }
    final considered = log.where((point) => point.tMs >= watermark).length;
    return (
      logPoints: log.length,
      consideredPoints: considered,
      detected: result.detected.length,
    );
  }

  /// Pure windowing: the finalised trainings the [log] yields given the last
  /// [watermark] and [now], plus the watermark to persist. Extracted from [run]
  /// so it is unit-testable without storage.
  ///
  /// Two rules keep a continuously-running service from mis-detecting:
  /// 1. It scans EVERY point from [watermark] on (not just a slice since the last
  ///    tick), so a long ride is seen whole — the watermark only ever advances
  ///    past a FINALISED training, never into the middle of an open segment.
  /// 2. It finalises only segments that ended at least [_tail] ago, so an
  ///    in-progress ride is deferred and later recorded with its full duration.
  ({List<CardioTraining> detected, int watermark}) selectDetections(
    List<TrackPoint> log,
    List<ActivitySample> activityLog,
    int watermark,
    DateTime now,
  ) {
    final considered = [
      for (final point in log)
        if (point.tMs >= watermark) point,
    ];
    if (considered.length < 2) {
      return (detected: const [], watermark: watermark);
    }
    final cutoff = now.subtract(_tail).millisecondsSinceEpoch;
    final detected = [
      for (final training in const CardioDetector().detect(considered, activityLog))
        if (training.endMs <= cutoff) training,
    ];
    var newWatermark = watermark;
    for (final training in detected) {
      if (training.endMs > newWatermark) {
        newWatermark = training.endMs;
      }
    }
    return (detected: detected, watermark: newWatermark);
  }

  Future<void> _addPending(
    List<CardioTraining> detected,
    Future<void> Function(CardioTraining) onDetected,
  ) async {
    final pending = await _store.loadPendingTrainings();
    final active = await _store.loadActiveTraining();
    final existing = [...await _store.loadTrainings(), ...pending];
    var changed = false;
    for (final training in detected) {
      final overlapsActive = active != null && training.endMs >= active.startMs;
      if (overlapsActive || _overlaps(training, existing)) {
        continue;
      }
      pending.add(training);
      existing.add(training);
      changed = true;
      await onDetected(training);
    }
    if (changed) {
      await _store.savePendingTrainings(pending);
    }
  }

  bool _overlaps(CardioTraining candidate, List<CardioTraining> all) {
    for (final other in all) {
      if (candidate.startMs <= other.endMs && other.startMs <= candidate.endMs) {
        return true;
      }
    }
    return false;
  }
}
