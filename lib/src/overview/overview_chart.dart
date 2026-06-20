import 'dart:collection';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

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
    final s = context.watch<ProfileGlucoseState>();
    final gc = Theme.of(context).extension<GlucoseColors>()!;
    final byTime = widget.byTime;
    if (byTime.isEmpty) {
      return Center(child: LocaleText('overview.chart.empty'));
    }
    final entries = byTime.entries.toList();
    final latestSecs = entries.last.key;
    // Only the last 24 h, even if more history is cached.
    final cutoff = latestSecs - 24 * 3600;
    // Y values are converted to the chosen display unit; X stays hours-ago.
    final spots = [
      for (final e in entries)
        if (e.key >= cutoff)
          FlSpot((e.key - latestSecs) / 3600.0, s.toDisplay(e.value)),
    ];
    final minX = spots.first.x;
    final maxY = s.toDisplay(300);
    // Whole-unit gridlines that read cleanly in either unit.
    final yInterval = s.unit == GlucoseUnit.mmol ? 3.0 : 50.0;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        minX: minX,
        maxX: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
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
              interval: yInterval,
              getTitlesWidget: (v, _) => Text(
                s.unit == GlucoseUnit.mmol
                    ? v.toStringAsFixed(0)
                    : '${v.toInt()}',
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
        // User-configurable target range band.
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: s.toDisplay(s.targetLow),
              color: gc.low.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
            HorizontalLine(
              y: s.toDisplay(s.targetHigh),
              color: gc.high.withValues(alpha: 0.4),
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
            color: gc.inRange,
            dotData: FlDotData(show: spots.length < 60),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  gc.inRange.withValues(alpha: 0.3),
                  gc.inRange.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
