import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/profile_developer_state.dart';
import 'package:insulink/src/profile/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// "Patterns": average glucose by hour-of-day across the whole cached history,
/// so recurring daily highs/lows stand out. A neutral median-style line with a
/// shaded ±1 SD deviation band around it (à la FreeStyle Libre).
class PatternsView extends StatelessWidget {
  const PatternsView({super.key});

  @override
  Widget build(BuildContext context) {
    final g7 = context.watch<G7Controller>();
    final s = context.watch<ProfileGlucoseState>();
    final theme = Theme.of(context);
    final gc = theme.extension<GlucoseColors>()!;

    // Long-term archive (spans sensor swaps): keyed by absolute epoch-minute, so
    // hour-of-day comes straight from the timestamp — no session start needed.
    final byTime = g7.archiveSince(G7Controller.statsWindow);
    if (byTime.isEmpty) {
      return Center(child: LocaleText('statistics.empty'));
    }

    // Per hour-of-day (0..23): mean and spread (via sum + sum of squares).
    final sums = List<double>.filled(24, 0);
    final sumSq = List<double>.filled(24, 0);
    final counts = List<int>.filled(24, 0);
    for (final e in byTime.entries) {
      final h = DateTime.fromMillisecondsSinceEpoch(e.key * 60000).hour;
      sums[h] += e.value;
      sumSq[h] += e.value * e.value.toDouble();
      counts[h] += 1;
    }

    // Mean + spread for the hours that actually have data.
    final stats = <int, ({double mean, double sd})>{};
    for (var h = 0; h < 24; h++) {
      if (counts[h] == 0) continue;
      final mean = sums[h] / counts[h];
      final variance = (sumSq[h] / counts[h] - mean * mean).clamp(0.0, 1e9);
      stats[h] = (mean: mean, sd: math.sqrt(variance));
    }
    if (stats.isEmpty) {
      return Center(child: LocaleText('statistics.empty'));
    }

    // Fill hours without readings by interpolating between the nearest known
    // hours. Hour-of-day is CIRCULAR (23:00 borders 00:00), so search both
    // directions WITH wraparound — this keeps the line continuous AND always
    // spanning the full 0..23, instead of dangling in mid-air when the archive
    // happens to lack the earliest/latest hours. (Dart's `%` is non-negative for
    // a positive divisor, so `(h - n) % 24` wraps correctly.)
    double interp(int h, double Function(({double mean, double sd}) v) sel) {
      final known = stats[h];
      if (known != null) return sel(known);
      var down = 1, up = 1;
      while (!stats.containsKey((h - down) % 24)) {
        down++;
      }
      while (!stats.containsKey((h + up) % 24)) {
        up++;
      }
      final t = down / (down + up);
      return sel(stats[(h - down) % 24]!) * (1 - t) +
          sel(stats[(h + up) % 24]!) * t;
    }

    final meanSpots = <FlSpot>[];
    final upperSpots = <FlSpot>[];
    final lowerSpots = <FlSpot>[];
    for (var h = 0; h <= 23; h++) {
      final mean = interp(h, (v) => v.mean);
      final sd = interp(h, (v) => v.sd);
      final x = h.toDouble();
      meanSpots.add(FlSpot(x, s.toDisplay(mean.round())));
      upperSpots.add(FlSpot(x, s.toDisplay((mean + sd).round().clamp(0, 300))));
      lowerSpots.add(FlSpot(x, s.toDisplay((mean - sd).round().clamp(0, 300))));
    }

    final maxY = s.toDisplay(300);
    final yInterval = s.unit == GlucoseUnit.mmol ? 3.0 : 50.0;
    // Neutral line + band that read well on both light and dark backgrounds.
    final lineColor = theme.colorScheme.onSurface.withValues(alpha: 0.85);
    final bandColor = theme.colorScheme.onSurface.withValues(alpha: 0.12);

    LineChartBarData edge(List<FlSpot> spots) => LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.2,
      preventCurveOverShooting: true,
      barWidth: 0,
      color: Colors.transparent,
      dotData: const FlDotData(show: false),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocaleText(
            'statistics.patterns.title',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          LocaleText(
            'statistics.patterns.hint',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          // Developer-only: how much real data backs the curve. A near-empty
          // archive (few readings / few covered hours) is why the line looks
          // linear — the rest is interpolated between the few real points.
          if (context.watch<ProfileDeveloperState>().enabled)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${byTime.length} readings · ${stats.length}/24 hours covered',
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 23,
                minY: 0,
                maxY: maxY,
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
                        '${v.toInt()}',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                // Target range band.
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
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  // 0 = lower edge, 1 = upper edge; the deviation band is filled
                  // between them. 2 = the mean line on top.
                  edge(lowerSpots),
                  edge(upperSpots),
                  LineChartBarData(
                    spots: meanSpots,
                    isCurved: true,
                    curveSmoothness: 0.2,
                    preventCurveOverShooting: true,
                    barWidth: 2.5,
                    color: lineColor,
                    dotData: const FlDotData(show: false),
                  ),
                ],
                betweenBarsData: [
                  BetweenBarsData(
                    fromIndex: 0,
                    toIndex: 1,
                    color: bandColor,
                  ),
                ],
              ),
              duration: Duration.zero,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
