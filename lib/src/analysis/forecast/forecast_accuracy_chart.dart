import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/analysis/forecast/forecast_accuracy.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';

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
    final scheme = Theme.of(context).colorScheme;
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: glucose.toDisplay(300),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: glucose.unit == GlucoseUnit.mmol ? 3.0 : 50.0,
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          _line(_spots((outcome) => outcome.actual), scheme.onSurface),
          _line(
            _spots((outcome) => outcome.predicted),
            scheme.primary,
            dashed: true,
          ),
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

  LineChartBarData _line(
    List<FlSpot> spots,
    Color color, {
    bool dashed = false,
  }) => LineChartBarData(
    spots: spots,
    isCurved: true,
    barWidth: 2,
    color: color,
    dashArray: dashed ? const [5, 4] : null,
    dotData: const FlDotData(show: false),
  );

  FlTitlesData _titles(BuildContext context) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          interval: glucose.unit == GlucoseUnit.mmol ? 3.0 : 50.0,
          getTitlesWidget: (value, _) => Text(
            glucose.unit == GlucoseUnit.mmol
                ? value.toStringAsFixed(0)
                : '${value.toInt()}',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
