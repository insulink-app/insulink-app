/// Pure remaining-life arithmetic for a sensor session, split out of
/// [SensorLifeBar] so it stays testable (inject [now] to avoid wall-clock
/// flakiness). The bar shows one segment per remaining unit — days normally,
/// switching to HOURS over the final day so the last day stays meaningful.
class SensorLifespan {
  SensorLifespan({
    required this.start,
    required this.sessionLengthSec,
    DateTime? now,
  }) : _now = now ?? DateTime.now();

  final DateTime start;
  final int sessionLengthSec;
  final DateTime _now;

  int get remainingSecs => sessionLengthSec - _now.difference(start).inSeconds;

  bool get expired => remainingSecs <= 0;

  /// Switch to hour-granularity once a single day or less remains (and the
  /// sensor hasn't expired) — the final day matters most, so show it in hours.
  bool get hoursMode => remainingSecs > 0 && remainingSecs <= 86400;

  /// Whole rated days. The reported session length includes a ~12 h grace
  /// period past the rated lifetime (10 d → 907200 s = 10.5 d), so floor — not
  /// round — to avoid showing an extra day (a 10-day sensor as "11").
  int get totalDays => (sessionLengthSec / 86400).floor().clamp(1, 30);

  /// Total bars to draw: 24 (one per hour) in the final day, else one per day.
  int get totalSegments => hoursMode ? 24 : totalDays;

  /// Filled bars, rounding a partial unit UP so the current hour/day still
  /// counts as remaining.
  int get filledSegments => hoursMode
      ? (remainingSecs / 3600).ceil().clamp(0, 24)
      : (remainingSecs / 86400).ceil().clamp(0, totalDays);
}
