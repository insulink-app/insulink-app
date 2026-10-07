/// Thins a dense series (pulse, GPS speed: a sample every second or so) to a
/// readable curve by averaging it over equal stretches of time. Averaging
/// rather than picking every n-th sample smooths the jitter instead of
/// sampling it, and keeps the curve's shape.
class SeriesThinning {
  const SeriesThinning({required this.spanMinutes});

  /// The chart's time span in minutes, the x axis the points live on.
  final double spanMinutes;

  /// At most this many stretches, so a long training still reads as a curve.
  static const int maxBuckets = 30;

  /// No stretch shorter than this, so a short training is smoothed too.
  static const double minBucketMinutes = 0.5;

  int get bucketCount =>
      (spanMinutes / minBucketMinutes).floor().clamp(1, maxBuckets);

  /// One averaged point (mean x, mean value) per non-empty stretch, in order.
  List<({double x, double value})> thin(
    List<({double x, double value})> points,
  ) {
    if (points.length <= bucketCount || spanMinutes <= 0) {
      return points;
    }
    final width = spanMinutes / bucketCount;
    final sums = <int, ({double x, double value, int count})>{};
    for (final point in points) {
      final bucket = (point.x / width).floor();
      final sum = sums[bucket];
      sums[bucket] = sum == null
          ? (x: point.x, value: point.value, count: 1)
          : (
              x: sum.x + point.x,
              value: sum.value + point.value,
              count: sum.count + 1,
            );
    }
    final buckets = sums.keys.toList()..sort();
    return [
      for (final bucket in buckets)
        (
          x: sums[bucket]!.x / sums[bucket]!.count,
          value: sums[bucket]!.value / sums[bucket]!.count,
        ),
    ];
  }
}
