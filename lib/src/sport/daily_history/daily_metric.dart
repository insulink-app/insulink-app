/// One day's total of a metric on a [DailyHistoryView].
typedef DailyValue = ({DateTime date, double value});

/// How a daily metric reads: its number format, unit and optional daily goal.
///
/// [summed] says whether the days add up to something (steps, carbs, bolus):
/// then the page leads with today and shows the total. A rate such as resting
/// heart rate does not add up, so it leads with the latest day and shows the
/// spread instead.
class DailyMetric {
  const DailyMetric({
    required this.format,
    this.unit,
    this.goal,
    this.summed = true,
  });

  final String Function(double value) format;
  final String? unit;

  /// The daily goal from the settings, or null when the metric has none.
  final double? goal;
  final bool summed;

  bool get hasGoal => (goal ?? 0) > 0;

  String labeled(double value) =>
      unit == null ? format(value) : '${format(value)} $unit';

  bool reached(double value) => hasGoal && value >= goal!;

  /// 0..1 of the way to the goal, 0 without one.
  double progress(double value) =>
      hasGoal ? (value / goal!).clamp(0.0, 1.0) : 0;
}
