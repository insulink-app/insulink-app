import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/analysis/forecast/forecast_accuracy.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// What the model said against what the sensor read, over the scored window.
///
/// Two lines on one time axis rather than a predicted-vs-actual scatter: the
/// question the tiles cannot answer is WHERE the forecast went wrong — the
/// post-meal rise it missed, the fall it called too late — and that only shows
/// against the clock.
class ForecastAccuracyChart extends StatelessWidget {
  const ForecastAccuracyChart({
    super.key,
    required this.outcomes,
    required this.glucose,
  });

  final List<ForecastOutcome> outcomes;
  final ProfileGlucoseState glucose;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: glucose.toDisplay(300),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: glucose.unit == GlucoseUnit.mmol ? 3.0 : 50.0,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.panelRaised, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          _line(_spots((outcome) => outcome.actual), colors.text),
          _line(_spots((outcome) => outcome.predicted), colors.accent),
        ],
      ),
      duration: Duration.zero,
    );
  }

  /// X is the index of the outcome, not its timestamp: the anchors sit on a
  /// regular grid, and indexing keeps a sensor gap from stretching the axis over
  /// a stretch nothing was scored on.
  List<FlSpot> _spots(int Function(ForecastOutcome outcome) value) => [
    for (var index = 0; index < outcomes.length; index++)
      FlSpot(index.toDouble(), glucose.toDisplay(value(outcomes[index]))),
  ];

  LineChartBarData _line(List<FlSpot> spots, Color color) => LineChartBarData(
    spots: spots,
    isCurved: true,
    barWidth: 2,
    color: color,
    dotData: const FlDotData(show: false),
  );

  /// Indices where a new day starts, thinned so labels keep a fifth of the
  /// width between them.
  Set<int> get _dayStarts {
    final starts = <int>{};
    var last = -outcomes.length;
    for (var index = 0; index < outcomes.length; index++) {
      final newDay =
          index == 0 || outcomes[index].at.day != outcomes[index - 1].at.day;
      if (newDay && index - last >= outcomes.length / 5) {
        starts.add(index);
        last = index;
      }
    }
    return starts;
  }

  FlTitlesData _titles(BuildContext context) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: 1,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (value != index || !_dayStarts.contains(index)) {
              return const SizedBox.shrink();
            }
            final weekday = outcomes[index].at.weekday;
            return SideTitleWidget(
              meta: meta,
              fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
              child: Text(
                Locales.string(context, 'date.weekday.$weekday'),
                style: InkText.axis.copyWith(
                  fontSize: 12,
                  color: context.ink.muted,
                ),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          interval: glucose.unit == GlucoseUnit.mmol ? 3.0 : 50.0,
          getTitlesWidget: (value, _) => Text(
            glucose.unit == GlucoseUnit.mmol
                ? value.toStringAsFixed(0)
                : '${value.toInt()}',
            style: InkText.axis.copyWith(
              fontSize: 12,
              color: context.ink.muted,
            ),
          ),
        ),
      ),
    );
  }
}
