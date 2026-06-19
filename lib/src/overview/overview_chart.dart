import 'dart:collection';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// fl_chart line graph of glucose vs. time (hours, 0 = latest reading).
class OverviewChart extends StatefulWidget {
  const OverviewChart({super.key, required this.byTime});

  final SplayTreeMap<int, int> byTime;

  @override
  State<OverviewChart> createState() => _OverviewChartState();
}

class _OverviewChartState extends State<OverviewChart> {
  /// Spot index under the finger on the last touch event, so we only buzz once
  /// per data point as the finger moves across (and reset when it lifts off).
  int? _lastTouchedIndex;

  /// Light haptic tick when the highlighted point changes while scrubbing.
  void _onChartTouch(FlTouchEvent event, LineTouchResponse? response) {
    final spots = response?.lineBarSpots;
    if (!event.isInterestedForInteractions || spots == null || spots.isEmpty) {
      _lastTouchedIndex = null;
      return;
    }
    final index = spots.first.spotIndex;
    if (index != _lastTouchedIndex) {
      _lastTouchedIndex = index;
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final byTime = widget.byTime;
    if (byTime.isEmpty) {
      return Center(child: LocaleText('overview.chart.empty'));
    }
    final entries = byTime.entries.toList();
    final latestSecs = entries.last.key;
    // Only the last 24 h, even if more history is cached.
    final cutoff = latestSecs - 24 * 3600;
    final spots = [
      for (final e in entries)
        if (e.key >= cutoff)
          FlSpot((e.key - latestSecs) / 3600.0, e.value.toDouble()),
    ];
    final minX = spots.first.x;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 300,
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
        lineTouchData: LineTouchData(enabled: true, touchCallback: _onChartTouch),
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
