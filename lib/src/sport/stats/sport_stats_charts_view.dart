import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/stats/sport_stats_charts.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:insulink/src/theme/status_colors.dart';

const int _dayMs = 86400000;

/// The whole-training overview charts, mirroring the web panel: how many
/// workouts per week, and how each routine's runs compare over time.
class SportStatsChartsView extends StatelessWidget {
  const SportStatsChartsView({
    super.key,
    required this.sessions,
    required this.routines,
  });

  final List<WorkoutSession> sessions;
  final List<SportRoutine> routines;

  @override
  Widget build(BuildContext context) {
    final weekly = weeklyWorkouts(sessions);
    final comparison = routineComparison(
      sessions,
      routines,
      Locales.string(context, 'sport.routines.new'),
      Locales.string(context, 'sport.workout.free'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, 'sport.stats.chart_frequency'),
        const SizedBox(height: 12),
        SizedBox(height: 200, child: _frequencyChart(context, weekly)),
        const SizedBox(height: 28),
        _heading(context, 'sport.stats.chart_comparison'),
        const SizedBox(height: 12),
        if (comparison.isEmpty)
          _emptyComparison(context)
        else ...[
          SizedBox(height: 220, child: _comparisonChart(context, comparison)),
          const SizedBox(height: 12),
          _legend(context, comparison),
        ],
      ],
    );
  }

  Widget _heading(BuildContext context, String key) => LocaleText(
    key,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
  );

  Widget _emptyComparison(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(
      child: LocaleText(
        'sport.stats.comparison_empty',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    ),
  );

  Widget _frequencyChart(BuildContext context, List<WeeklyBucket> weekly) {
    final scheme = Theme.of(context).colorScheme;
    final maxCount = weekly.fold(
      0,
      (max, bucket) => bucket.count > max ? bucket.count : max,
    );
    final topY = (maxCount + 1).toDouble();
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: topY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.onSurface.withValues(alpha: 0.06),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, _) => value == value.roundToDouble()
                  ? _axisText(context, '${value.toInt()}')
                  : const SizedBox.shrink(),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, _) =>
                  _weekLabel(context, weekly, value.toInt()),
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItem: (_, _, rod, _) => BarTooltipItem(
              '${rod.toY.toInt()}',
              TextStyle(
                color: scheme.onInverseSurface,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
        barGroups: [
          for (var index = 0; index < weekly.length; index++)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: weekly[index].count.toDouble(),
                  width: 10,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      scheme.primary.withValues(alpha: 0.55),
                      scheme.primary,
                    ],
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: topY,
                    color: scheme.onSurface.withValues(alpha: 0.04),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Only the first and last week get a date tick, to avoid crowding.
  Widget _weekLabel(
    BuildContext context,
    List<WeeklyBucket> weekly,
    int index,
  ) {
    if (index != 0 && index != weekly.length - 1) {
      return const SizedBox.shrink();
    }
    final date = DateTime.fromMillisecondsSinceEpoch(weekly[index].weekStartMs);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: _axisText(context, '${date.day}.${date.month}.'),
    );
  }

  Widget _comparisonChart(BuildContext context, List<RoutineSeries> series) {
    final palette = _palette(context);
    final allMs = [
      for (final line in series)
        for (final point in line.points) point.atMs,
    ];
    final minMs = allMs.reduce((a, b) => a < b ? a : b);
    final maxMs = allMs.reduce((a, b) => a > b ? a : b);
    final spanDays = ((maxMs - minMs) / _dayMs).clamp(1, double.infinity);
    final scheme = Theme.of(context).colorScheme;
    // Only fill under a lone line — overlapping tinted areas muddy each other.
    final fill = series.length == 1;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: spanDays.toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.onSurface.withValues(alpha: 0.06),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, _) =>
                  _axisText(context, _compact(value)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (spanDays / 4).ceilToDouble(),
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _axisText(context, _dateLabel(minMs, value)),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  _compact(spot.y),
                  TextStyle(
                    color: scheme.onInverseSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (var index = 0; index < series.length; index++)
            LineChartBarData(
              spots: [
                for (final point in series[index].points)
                  FlSpot((point.atMs - minMs) / _dayMs, point.value),
              ],
              isCurved: true,
              curveSmoothness: 0.2,
              preventCurveOverShooting: true,
              barWidth: 2.5,
              color: palette[index % palette.length],
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, bar, _) => FlDotCirclePainter(
                  radius: 3,
                  color: scheme.surface,
                  strokeWidth: 2,
                  strokeColor: bar.color ?? scheme.primary,
                ),
              ),
              belowBarData: BarAreaData(
                show: fill,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    palette[index % palette.length].withValues(alpha: 0.22),
                    palette[index % palette.length].withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Short axis/tooltip number: drops the decimal, and folds thousands to "1.2k"
  /// so a big workout score doesn't need a 36px gutter of digits.
  String _compact(double value) {
    if (value.abs() >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toStringAsFixed(0);
  }

  Widget _legend(BuildContext context, List<RoutineSeries> series) {
    final palette = _palette(context);
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        for (var index = 0; index < series.length; index++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: palette[index % palette.length],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(series[index].name, style: const TextStyle(fontSize: 12)),
            ],
          ),
      ],
    );
  }

  String _dateLabel(int minMs, double value) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      minMs + (value * _dayMs).round(),
    );
    return '${date.day}.${date.month}.';
  }

  Widget _axisText(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 10,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  /// Distinct series colours drawn from theme tokens (no invented hexes), cycled
  /// when there are more routines than colours.
  List<Color> _palette(BuildContext context) => [
    Theme.of(context).colorScheme.primary,
    context.warning,
    context.positive,
    context.accent,
    context.danger,
  ];
}
