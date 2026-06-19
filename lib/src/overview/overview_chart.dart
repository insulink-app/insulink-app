import 'dart:collection';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// fl_chart line graph of glucose vs. time (hours, 0 = latest reading).
class OverviewChart extends StatelessWidget {
  const OverviewChart({super.key, required this.byTime});

  final SplayTreeMap<int, int> byTime;

  @override
  Widget build(BuildContext context) {
    if (byTime.isEmpty) {
      return Center(child: LocaleText('overview.chart.empty'));
    }
    final entries = byTime.entries.toList();
    final latestSecs = entries.last.key;
    final spots = [
      for (final e in entries)
        FlSpot((e.key - latestSecs) / 3600.0, e.value.toDouble()),
    ];
    final maxY =
        (entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 30)
            .clamp(200, 400)
            .toDouble();
    final minX = spots.first.x;

    return LineChart(
      LineChartData(
        minY: 40,
        maxY: maxY,
        minX: minX,
        maxX: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 50,
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
              interval: 50,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 6,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}h',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
        ),
        // Target range band 70–180 mg/dL.
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 70,
              color: Colors.red.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
            HorizontalLine(
              y: 180,
              color: Colors.orange.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ],
        ),
        lineTouchData: const LineTouchData(enabled: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            barWidth: 3,
            color: Colors.tealAccent,
            dotData: FlDotData(show: spots.length < 60),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.tealAccent.withValues(alpha: 0.3),
                  Colors.tealAccent.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
