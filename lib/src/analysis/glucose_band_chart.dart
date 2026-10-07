import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:insulink/src/overview/chart/glucose_y_labels.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// A glucose line with a shaded spread band around it, in front of the target
/// range: the patterns (Ø per hour of day) and the history (Ø per day). No
/// grid; the target range lightly behind, its bounds dashed and the only y
/// labels. The y range fits the band and the targets.
class GlucoseBandChart extends StatelessWidget {
  const GlucoseBandChart({
    super.key,
    required this.meanSpots,
    required this.upperSpots,
    required this.lowerSpots,
    required this.glucose,
    required this.colors,
    required this.minX,
    required this.maxX,
    required this.xInterval,
    required this.xLabel,
    this.dots = false,
  });

  final List<FlSpot> meanSpots, upperSpots, lowerSpots;
  final ProfileGlucoseState glucose;
  final GlucoseColors colors;
  final double minX, maxX, xInterval;

  /// The label under a tick, or null for none.
  final String? Function(double x) xLabel;

  /// Dots on the line, for a few points (one per day).
  final bool dots;

  static const double _labelStrip = 36;
  static const double _bottomStrip = 28;

  double get _low => glucose.toDisplay(glucose.targetLow);
  double get _high => glucose.toDisplay(glucose.targetHigh);

  double get _minY {
    final lowest = lowerSpots.map((spot) => spot.y).fold(_low, math.min);
    return lowest - (_high - _low) * 0.15;
  }

  double get _maxY {
    final highest = upperSpots.map((spot) => spot.y).fold(_high, math.max);
    return highest + (_high - _low) * 0.15;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        LineChart(_data(context), duration: Duration.zero),
        Positioned.fill(
          child: IgnorePointer(
            child: GlucoseYLabels(
              values: [_low, _high],
              minY: _minY,
              maxY: _maxY,
              stripWidth: _labelStrip,
              bottomInset: _bottomStrip,
              leading: true,
              format: (value) => glucose.unit == GlucoseUnit.mmol
                  ? value.toStringAsFixed(1).replaceFirst('.', ',')
                  : '${value.round()}',
            ),
          ),
        ),
      ],
    );
  }

  LineChartData _data(BuildContext context) {
    final ink = context.ink;
    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: _minY,
      maxY: _maxY,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: _titles(ink),
      rangeAnnotations: RangeAnnotations(
        horizontalRangeAnnotations: [
          HorizontalRangeAnnotation(
            y1: _low,
            y2: _high,
            color: colors.inRange.withValues(alpha: 0.05),
          ),
        ],
      ),
      extraLinesData: ExtraLinesData(
        horizontalLines: [_bound(_low, colors.low), _bound(_high, colors.high)],
      ),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: _bars(ink),
      betweenBarsData: [
        BetweenBarsData(
          fromIndex: 0,
          toIndex: 1,
          color: ink.accent.withValues(alpha: 0.16),
        ),
      ],
    );
  }

  HorizontalLine _bound(double y, Color color) => HorizontalLine(
    y: y,
    color: color.withValues(alpha: 0.7),
    strokeWidth: 1,
    dashArray: const [2, 4],
  );

  FlTitlesData _titles(InsulinkColors ink) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: _labelStrip,
          interval: _maxY - _minY,
          getTitlesWidget: (_, _) => const SizedBox.shrink(),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: _bottomStrip,
          interval: xInterval,
          getTitlesWidget: (value, meta) {
            final label = xLabel(value);
            if (label == null) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              child: Text(
                label,
                style: InkText.axis.copyWith(fontSize: 13, color: ink.muted),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 0 = lower edge, 1 = upper edge (the spread band fills between them);
  /// 2 = the line on top.
  List<LineChartBarData> _bars(InsulinkColors ink) {
    return [
      _edge(lowerSpots),
      _edge(upperSpots),
      LineChartBarData(
        spots: meanSpots,
        isCurved: true,
        curveSmoothness: 0.2,
        preventCurveOverShooting: true,
        barWidth: 2.5,
        color: ink.text,
        dotData: FlDotData(
          show: dots,
          getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
            radius: 4,
            color: ink.text,
            strokeColor: ink.panel,
            strokeWidth: 2.5,
          ),
        ),
      ),
    ];
  }

  /// An invisible curve marking one edge of the spread band.
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
