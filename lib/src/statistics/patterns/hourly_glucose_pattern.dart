import 'dart:math' as math;

/// Mean + standard deviation of glucose per hour-of-day, the data behind the
/// patterns chart. UI-agnostic (no chart/widget types) so it stays testable.
class HourlyGlucosePattern {
  HourlyGlucosePattern(this.readings);

  /// Archived readings keyed by absolute epoch-minute → mg/dL.
  final Map<int, int> readings;

  /// Mean + SD for every hour 0..23, interpolating hours without data from the
  /// nearest known hours (circular: 23 borders 0). Empty when there are no
  /// readings at all.
  List<({int hour, double mean, double sd})> build() {
    final stats = _hourlyStats();
    if (stats.isEmpty) {
      return const [];
    }
    return [
      for (var hour = 0; hour <= 23; hour++)
        (
          hour: hour,
          mean: _interpolate(stats, hour, (entry) => entry.mean),
          sd: _interpolate(stats, hour, (entry) => entry.sd),
        ),
    ];
  }

  /// Mean + spread for the hours that actually have data (via sum + sum of
  /// squares). Readings arrive ~every 5 min, so the per-hour count is a faithful
  /// weighting.
  Map<int, ({double mean, double sd})> _hourlyStats() {
    final sums = List<double>.filled(24, 0);
    final sumSquares = List<double>.filled(24, 0);
    final counts = List<int>.filled(24, 0);
    for (final entry in readings.entries) {
      final hour = DateTime.fromMillisecondsSinceEpoch(entry.key * 60000).hour;
      sums[hour] += entry.value;
      sumSquares[hour] += entry.value * entry.value.toDouble();
      counts[hour] += 1;
    }
    final stats = <int, ({double mean, double sd})>{};
    for (var hour = 0; hour < 24; hour++) {
      if (counts[hour] == 0) {
        continue;
      }
      final mean = sums[hour] / counts[hour];
      final variance = (sumSquares[hour] / counts[hour] - mean * mean).clamp(
        0.0,
        1e9,
      );
      stats[hour] = (mean: mean, sd: math.sqrt(variance));
    }
    return stats;
  }

  /// Value for [hour], interpolated between the nearest known hours in both
  /// directions WITH wraparound, so the line stays continuous and always spans
  /// the full 0..23. (Dart's `%` is non-negative for a positive divisor.)
  double _interpolate(
    Map<int, ({double mean, double sd})> stats,
    int hour,
    double Function(({double mean, double sd}) entry) select,
  ) {
    final known = stats[hour];
    if (known != null) {
      return select(known);
    }
    var down = 1, up = 1;
    while (!stats.containsKey((hour - down) % 24)) {
      down++;
    }
    while (!stats.containsKey((hour + up) % 24)) {
      up++;
    }
    final weight = down / (down + up);
    return select(stats[(hour - down) % 24]!) * (1 - weight) +
        select(stats[(hour + up) % 24]!) * weight;
  }
}
