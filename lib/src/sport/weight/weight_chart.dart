import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/sport/sport_models.dart';

/// Weight over time as a line — X = timestamp (true spacing for uneven gaps), Y
/// scaled automatically with a little margin. Expects [weights] already filtered
/// by time window and sorted ascending. A single point is drawn as a dot.
class WeightChart extends StatelessWidget {
  const WeightChart({super.key, required this.weights});

  final List<WeightEntry> weights;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final spots = [
      for (final entry in weights) FlSpot(entry.atEpochMs.toDouble(), entry.kg),
    ];
    final values = weights.map((entry) => entry.kg);
    final minKg = values.reduce((a, b) => a < b ? a : b);
    final maxKg = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxKg - minKg) < 1 ? 1.0 : (maxKg - minKg) * 0.2;
    final minX = weights.first.atEpochMs.toDouble();
    final maxX = weights.last.atEpochMs.toDouble();

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX == minX ? minX + 1 : maxX,
        minY: minKg - pad,
        maxY: maxKg + pad,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context, onSurface, minX, maxX),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            preventCurveOverShooting: true,
            barWidth: 2.5,
            color: onSurface.withValues(alpha: 0.85),
            dotData: FlDotData(show: weights.length == 1),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  FlTitlesData _titles(
    BuildContext context,
    Color onSurface,
    double minX,
    double maxX,
  ) {
    final locale = MaterialLocalizations.of(context);
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: maxX > minX ? (maxX - minX) : null,
          getTitlesWidget: (value, meta) {
            if (value > minX && value < maxX) {
              return const SizedBox.shrink();
            }
            final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
            return SideTitleWidget(
              meta: meta,
              fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
              child: Text(
                locale.formatShortDate(date),
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(
              value.toStringAsFixed(0),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }
}
