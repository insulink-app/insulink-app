import 'cardio_models.dart';

/// Maps a detected GPS segment to a [CardioType] using the recognised activity
/// over the segment's time window when available — rejecting a bus/train
/// (`vehicle`) and confirming a real ride — and falling back to average speed
/// when no activity data covers the window. Pure and plugin-free so it stays
/// unit-testable.
class CardioActivityClassifier {
  const CardioActivityClassifier();

  /// The training type for a segment, or null to DISCARD it (recognised as a
  /// vehicle — the bus/train false-positive the speed heuristic can't catch).
  CardioType? classify({
    required int startMs,
    required int endMs,
    required double avgKmh,
    required List<ActivitySample> activityLog,
  }) {
    switch (_dominant(startMs, endMs, activityLog)) {
      case ActivityKind.vehicle:
        return null;
      case ActivityKind.bike:
        return CardioType.bike;
      case ActivityKind.run:
        return CardioType.jog;
      case ActivityKind.walk:
        return CardioType.walk;
      case ActivityKind.still:
      case ActivityKind.unknown:
      case null:
        return _bySpeed(avgKmh);
    }
  }

  CardioType _bySpeed(double avgKmh) {
    if (avgKmh > 15) {
      return CardioType.bike;
    }
    if (avgKmh > 7) {
      return CardioType.jog;
    }
    return CardioType.walk;
  }

  /// The activity kind that covered the most of the `[startMs, endMs]` window.
  /// The log holds one entry per change, so each entry's kind persists until the
  /// next; we sum each such interval's overlap with the window. Null when no
  /// activity data overlaps.
  ActivityKind? _dominant(int startMs, int endMs, List<ActivitySample> log) {
    final durations = <ActivityKind, int>{};
    for (var index = 0; index < log.length; index++) {
      final from = log[index].tMs;
      final until = index + 1 < log.length ? log[index + 1].tMs : endMs;
      final overlap = _overlapMs(startMs, endMs, from, until);
      if (overlap > 0) {
        durations.update(
          log[index].kind,
          (value) => value + overlap,
          ifAbsent: () => overlap,
        );
      }
    }
    if (durations.isEmpty) {
      return null;
    }
    return durations.entries
        .reduce((best, entry) => entry.value > best.value ? entry : best)
        .key;
  }

  int _overlapMs(int aStart, int aEnd, int bStart, int bEnd) {
    final start = aStart > bStart ? aStart : bStart;
    final end = aEnd < bEnd ? aEnd : bEnd;
    return end > start ? end - start : 0;
  }
}
