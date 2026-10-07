import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/stats/sport_stats_charts.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

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
    final colors = context.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, 'sport.stats.chart_frequency', _average(weekly)),
        InkPanel(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
          child: SizedBox(
            height: 200,
            child: _frequencyChart(context, colors, weekly),
          ),
        ),
        _heading(context, 'sport.stats.chart_comparison', null),
        InkPanel(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: comparison.isEmpty
              ? _emptyComparison(context)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _legend(context, colors, comparison),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: _comparisonChart(context, colors, comparison),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// "Ø 3,8": workouts per week over the shown weeks.
  String _average(List<WeeklyBucket> weekly) {
    if (weekly.isEmpty) {
      return '';
    }
    final total = weekly.fold(0, (sum, bucket) => sum + bucket.count);
    return 'Ø ${sportDecimal(total / weekly.length, 1)}';
  }

  /// A section title with an optional muted note on its right.
  Widget _heading(BuildContext context, String key, String? note) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 28, 8, 12),
      child: Row(
        children: [
          Expanded(child: LocaleText(key, style: InkText.section)),
          if (note != null)
            Text(note, style: InkText.label.copyWith(color: context.ink.muted)),
        ],
      ),
    );
  }

  Widget _emptyComparison(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(
      child: LocaleText(
        'sport.stats.comparison_empty',
        textAlign: TextAlign.center,
        style: InkText.label.copyWith(color: context.ink.muted),
      ),
    ),
  );

  /// Narrow round bars with their count above them, no y axis: the current
  /// week full accent, earlier ones at 55 %, a week without a workout as a
  /// flat 3 px dash in the line colour.
  Widget _frequencyChart(
    BuildContext context,
    InsulinkColors colors,
    List<WeeklyBucket> weekly,
  ) {
    final maxCount = weekly.fold(
      0,
      (max, bucket) => bucket.count > max ? bucket.count : max,
    );
    final topY = (maxCount + 1.5).toDouble();
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: topY,
        minY: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.line, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, _) =>
                  _weekLabel(context, weekly, value.toInt()),
            ),
          ),
        ),
        barTouchData: BarTouchData(
          enabled: false,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 4,
            getTooltipItem: (_, _, rod, _) => BarTooltipItem(
              rod.toY < 0.5 ? '' : '${rod.toY.toInt()}',
              InkText.caption.copyWith(
                color: colors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        barGroups: [
          for (var index = 0; index < weekly.length; index++)
            _bar(
              colors,
              index,
              weekly[index].count,
              index == weekly.length - 1,
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  BarChartGroupData _bar(
    InsulinkColors colors,
    int index,
    int count,
    bool current,
  ) {
    final empty = count == 0;
    return BarChartGroupData(
      x: index,
      showingTooltipIndicators: empty ? const [] : const [0],
      barRods: [
        BarChartRodData(
          toY: empty ? 0.1 : count.toDouble(),
          width: 14,
          borderRadius: BorderRadius.circular(empty ? 1.5 : 7),
          color: empty
              ? colors.line
              : current
              ? colors.accent
              : colors.accent.withValues(alpha: 0.55),
        ),
      ],
    );
  }

  /// A date under every fourth week, counted back from the current one.
  Widget _weekLabel(
    BuildContext context,
    List<WeeklyBucket> weekly,
    int index,
  ) {
    if ((weekly.length - 1 - index) % 4 != 0) {
      return const SizedBox.shrink();
    }
    final date = DateTime.fromMillisecondsSinceEpoch(weekly[index].weekStartMs);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: _axisText(context, '${date.day}.${date.month}.'),
    );
  }

  /// Each routine's score over time: lines with small filled points, the
  /// chart from the left edge without a y axis.
  Widget _comparisonChart(
    BuildContext context,
    InsulinkColors colors,
    List<RoutineSeries> series,
  ) {
    final palette = _palette(colors);
    final allMs = [
      for (final line in series)
        for (final point in line.points) point.atMs,
    ];
    final minMs = allMs.reduce((a, b) => a < b ? a : b);
    final maxMs = allMs.reduce((a, b) => a > b ? a : b);
    final spanDays = ((maxMs - minMs) / _dayMs).clamp(1, double.infinity);
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: spanDays.toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.line, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (spanDays / 4).ceilToDouble(),
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                child: _axisText(context, _dateLabel(minMs, value)),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) =>
                Theme.of(context).colorScheme.inverseSurface,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  _compact(spot.y),
                  TextStyle(
                    color: Theme.of(context).colorScheme.onInverseSurface,
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
                  color: bar.color ?? colors.accent,
                  strokeWidth: 0,
                ),
              ),
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  /// Short tooltip number: drops the decimal, and folds thousands to "1.2k".
  String _compact(double value) {
    if (value.abs() >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toStringAsFixed(0);
  }

  /// The routines as short strokes in their line's colour, above the chart.
  Widget _legend(
    BuildContext context,
    InsulinkColors colors,
    List<RoutineSeries> series,
  ) {
    final palette = _palette(colors);
    return Wrap(
      spacing: 18,
      runSpacing: 10,
      children: [
        for (var index = 0; index < series.length; index++)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 7,
            children: [
              Container(
                width: 16,
                height: 2.5,
                decoration: BoxDecoration(
                  color: palette[index % palette.length],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                series[index].name,
                style: InkText.label.copyWith(color: colors.muted),
              ),
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
    style: InkText.axis.copyWith(fontSize: 12, color: context.ink.muted),
  );

  /// Accent, violet and teal first (the design's three), then the glucose
  /// high and low tones, cycled for more routines.
  List<Color> _palette(InsulinkColors colors) => [
    colors.accent,
    colors.pulseHigh,
    colors.pace,
    colors.high,
    colors.low,
  ];
}
