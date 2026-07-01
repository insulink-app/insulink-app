import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/sport/sport_models.dart';

/// Daily values of an activity metric as bars (X = day, ascending). Expects
/// [days] already filtered by time window and sorted ascending. [value] pulls
/// the metric to display out of a day.
class ActivityBarChart extends StatelessWidget {
  const ActivityBarChart({
    super.key,
    required this.days,
    required this.value,
    required this.color,
  });

  final List<DailyActivity> days;
  final double Function(DailyActivity day) value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final locale = MaterialLocalizations.of(context);
    final maxY = days.map(value).fold<double>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY <= 0 ? 1 : maxY * 1.15,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: _titles(locale),
        barGroups: [
          for (var index = 0; index < days.length; index++)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: value(days[index]),
                  color: color,
                  width: (260 / days.length).clamp(2, 14).toDouble(),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
              ],
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  FlTitlesData _titles(MaterialLocalizations locale) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 42,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(
              value >= 1000
                  ? '${(value / 1000).toStringAsFixed(0)}k'
                  : value.toStringAsFixed(0),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index != 0 && index != days.length - 1) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
              child: Text(
                locale.formatShortDate(days[index].date),
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            );
          },
        ),
      ),
    );
  }
}
