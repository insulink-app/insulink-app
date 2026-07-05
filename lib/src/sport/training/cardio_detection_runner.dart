import '../sport_store.dart';
import 'cardio_detector.dart';
import 'cardio_models.dart';

/// Scans the background GPS + activity logs for finished endurance trainings and
/// adds new ones to the pending list (awaiting the user's confirm/reject),
/// invoking [onDetected] for each so the caller can raise a notification. Runs in
/// the foreground-service isolate off the watchdog tick.
///
/// `ponytail:` only considers points older than [_tail] so a still-in-progress
/// ride isn't finalised early, and advances the watermark to that cutoff — the
/// simplest way to avoid re-detecting without tracking open segments.
class CardioDetectionRunner {
  final SportStore _store;

  CardioDetectionRunner([this._store = const SportStore()]);

  /// Segments closer to now than this may still be an ongoing ride, so they are
  /// left for a later tick (matches the detector's own gap/pause tolerances).
  static const _tail = Duration(minutes: 5);

  Future<void> run(Future<void> Function(CardioTraining) onDetected) async {
    final log = await _store.loadLocationLog();
    if (log.isEmpty) {
      return;
    }
    final cutoff = DateTime.now().subtract(_tail).millisecondsSinceEpoch;
    final watermark = await _store.loadDetectWatermark() ?? 0;
    final fresh = [
      for (final point in log)
        if (point.tMs > watermark && point.tMs <= cutoff) point,
    ];
    if (fresh.length < 2) {
      return;
    }
    await _store.saveDetectWatermark(cutoff);
    final detected = const CardioDetector().detect(
      fresh,
      await _store.loadActivityLog(),
    );
    if (detected.isNotEmpty) {
      await _addPending(detected, onDetected);
    }
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
