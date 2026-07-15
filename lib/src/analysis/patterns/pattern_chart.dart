import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';

/// The patterns line chart: a neutral mean line with a shaded ±1 SD deviation
/// band, plus the target-range guide lines. Axes render in the display unit.
class PatternChart extends StatelessWidget {
  const PatternChart({
    super.key,
    required this.meanSpots,
    required this.upperSpots,
    required this.lowerSpots,
    required this.glucose,
    required this.colors,
  });

  final List<FlSpot> meanSpots, upperSpots, lowerSpots;
  final ProfileGlucoseState glucose;
  final GlucoseColors colors;

  double get _maxY => glucose.toDisplay(300);
  double get _yInterval => glucose.unit == GlucoseUnit.mmol ? 3.0 : 50.0;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 23,
        minY: 0,
        maxY: _maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _yInterval,
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context),
        extraLinesData: _targetLines(),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: _bars(onSurface),
        betweenBarsData: [
          BetweenBarsData(
            fromIndex: 0,
            toIndex: 1,
            color: onSurface.withValues(alpha: 0.12),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  FlTitlesData _titles(BuildContext context) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          interval: _yInterval,
          getTitlesWidget: (value, _) => _axisLabel(context, _formatY(value)),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: 6,
          getTitlesWidget: (value, _) =>
              _axisLabel(context, '${value.toInt()}'),
        ),
      ),
    );
  }

  String _formatY(double value) => glucose.unit == GlucoseUnit.mmol
      ? value.toStringAsFixed(0)
      : '${value.toInt()}';

  Widget _axisLabel(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 10,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  ExtraLinesData _targetLines() {
    return ExtraLinesData(
      horizontalLines: [
        HorizontalLine(
          y: glucose.toDisplay(glucose.targetLow),
          color: colors.low.withValues(alpha: 0.4),
          strokeWidth: 1,
        ),
        HorizontalLine(
          y: glucose.toDisplay(glucose.targetHigh),
          color: colors.high.withValues(alpha: 0.4),
          strokeWidth: 1,
        ),
      ],
    );
  }

  /// 0 = lower edge, 1 = upper edge (the deviation band fills between them);
  /// 2 = the mean line on top.
  List<LineChartBarData> _bars(Color lineColor) {
    return [
      _edge(lowerSpots),
      _edge(upperSpots),
      LineChartBarData(
        spots: meanSpots,
        isCurved: true,
        curveSmoothness: 0.2,
        preventCurveOverShooting: true,
        barWidth: 2.5,
        color: lineColor.withValues(alpha: 0.85),
        dotData: const FlDotData(show: false),
      ),
    ];
  }

  /// An invisible curve marking one edge of the deviation band.
  LineChartBarData _edge(List<FlSpot> spots) => LineChartBarData(
    spots: spots,
    isCurved: true,
    curveSmoothness: 0.2,
    preventCurveOverShooting: true,
    barWidth: 0,
    color: Colors.transparent,
    dotData: const FlDotData(show: false),
  );
}
