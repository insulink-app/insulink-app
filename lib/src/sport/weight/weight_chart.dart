import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/sport/sport_models.dart';

/// Gewicht über die Zeit als Linie (X = Eintrags-Index, aufsteigend). Bewusst
/// schlicht — gleiches fl_chart-Rezept wie `glucose_history_view.dart`, ohne
/// Zielbänder. Ein einzelner Punkt wird als Punkt gezeichnet.
class WeightChart extends StatelessWidget {
  const WeightChart({super.key, required this.weights});

  final List<WeightEntry> weights;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final spots = [
      for (var index = 0; index < weights.length; index++)
        FlSpot(index.toDouble(), weights[index].kg),
    ];
    final values = weights.map((entry) => entry.kg);
    final minKg = values.reduce((a, b) => a < b ? a : b);
    final maxKg = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxKg - minKg) < 1 ? 1.0 : (maxKg - minKg) * 0.2;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (weights.length - 1).clamp(1, double.infinity).toDouble(),
        minY: minKg - pad,
        maxY: maxKg + pad,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: _titles(onSurface),
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

  FlTitlesData _titles(Color onSurface) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          getTitlesWidget: (value, _) => Text(
            value.toStringAsFixed(0),
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}
