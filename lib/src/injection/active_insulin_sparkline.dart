import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// The IOB curve stripped to a sparkline: no axes, no grid, no touch — just the
/// shape of the insulin rising at each bolus and decaying away, with a dashed
/// marker on where "now" sits so the decayed past reads apart from the
/// projection.
///
/// The overview box used to say the same thing in two lines of grey text
/// ("active until", "last dose"). This is what those sentences were describing,
/// and it needs no reading: the curve's slope IS how fast it is going, and the
/// distance from the now-marker to the end IS how long is left. The full
/// [ActiveInsulinChart] on the detail page keeps the labelled axes.
class ActiveInsulinSparkline extends StatelessWidget {
  const ActiveInsulinSparkline({
    super.key,
    required this.points,
    required this.now,
  });

  final List<({DateTime at, double units})> points;
  final DateTime now;

  double get _spanMin =>
      points.last.at.difference(points.first.at).inSeconds / 60;

  double get _maxY {
    final peak = points.fold(0.0, (max, point) => point.units > max ? point.units : max);
    return (peak * 1.1).clamp(1.0, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Same guard as [ActiveInsulinChart]: everything below reads `points.first`
    // and `points.last`, and an empty list throws during layout.
    if (points.length < 2) {
      return const SizedBox.shrink();
    }
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: _spanMin == 0 ? 1 : _spanMin,
        minY: 0,
        maxY: _maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        extraLinesData: _nowLine(scheme),
        lineBarsData: [_iobBar(scheme)],
      ),
      duration: Duration.zero,
    );
  }

  LineChartBarData _iobBar(ColorScheme scheme) {
    return LineChartBarData(
      spots: [
        for (final point in points)
          FlSpot(
            point.at.difference(points.first.at).inSeconds / 60,
            point.units,
          ),
      ],
      isCurved: true,
      curveSmoothness: 0.15,
      preventCurveOverShooting: true,
      barWidth: 2,
      color: scheme.primary,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.28),
            scheme.primary.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }

  ExtraLinesData _nowLine(ColorScheme scheme) {
    return ExtraLinesData(
      verticalLines: [
        VerticalLine(
          x: now.difference(points.first.at).inSeconds / 60,
          color: scheme.onSurface.withValues(alpha: 0.3),
          strokeWidth: 1,
          dashArray: const [3, 3],
        ),
      ],
    );
  }
}
