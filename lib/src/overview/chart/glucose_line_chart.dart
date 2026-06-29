import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';

/// The fl_chart line graph itself: axes, target-range band and the touch
/// tooltip/indicator. Receives ready-made bars (zone runs + the transparent
/// touch overlay) and only assembles the chart config around them.
class GlucoseLineChart extends StatelessWidget {
  const GlucoseLineChart({
    super.key,
    required this.bars,
    required this.touchBarIndex,
    required this.shift,
    required this.rangeHours,
    required this.anchor,
    required this.glucose,
    required this.colors,
    required this.onChartTouch,
  });

  final List<LineChartBarData> bars;

  /// Index of the transparent overlay bar that owns touch.
  final int touchBarIndex;

  /// Phase shift placing full clock hours on integer x (also the max x).
  final double shift;
  final int rangeHours;

  /// Wall-clock time at x == shift; null falls back to "Nh ago" labels.
  final DateTime? anchor;
  final ProfileGlucoseState glucose;
  final GlucoseColors colors;
  final void Function(FlTouchEvent, LineTouchResponse?) onChartTouch;

  double get _maxY => glucose.toDisplay(300);

  /// Whole-unit gridlines that read cleanly in either unit.
  double get _yInterval => glucose.unit == GlucoseUnit.mmol ? 3.0 : 50.0;

  /// Fewer X ticks for shorter windows so labels don't crowd.
  double get _xInterval {
    if (rangeHours <= 6) {
      return 2.0;
    }
    return rangeHours <= 12 ? 3.0 : 6.0;
  }

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: _maxY,
        minX: shift - rangeHours,
        maxX: shift,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _yInterval,
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context),
        extraLinesData: _targetBand(),
        lineTouchData: _touchData(context),
        lineBarsData: bars,
      ),
      // No implicit morph animation: the number of zone bars changes between
      // states, so fl_chart would interpolate between mismatched structures —
      // which looked broken on load/update. Render each state directly.
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
          getTitlesWidget: (value, _) => _label(_formatY(value)),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: _xInterval,
          // Drop the fractional min/max edge ticks so only full hours show.
          minIncluded: false,
          maxIncluded: false,
          getTitlesWidget: (value, _) => _label(_xLabel(context, value)),
        ),
      ),
    );
  }

  Widget _label(String text) =>
      Text(text, style: const TextStyle(fontSize: 10, color: Colors.grey));

  String _formatY(double value) => glucose.unit == GlucoseUnit.mmol
      ? value.toStringAsFixed(0)
      : '${value.toInt()}';

  /// value is in shifted hours; (value - shift) hours back from the anchor lands
  /// on a full clock hour. Without an anchor, fall back to "Nh" offsets.
  String _xLabel(BuildContext context, double value) {
    if (anchor == null) {
      return '${value.toInt()}h';
    }
    final time = anchor!.add(
      Duration(seconds: ((value - shift) * 3600).round()),
    );
    return Locales.string(
      context,
      'overview.chart.hour',
      params: ['${time.hour}'],
    );
  }

  /// User-configurable target range band.
  ExtraLinesData _targetBand() {
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

  LineTouchData _touchData(BuildContext context) {
    final theme = Theme.of(context);
    return LineTouchData(
      enabled: true,
      touchCallback: onChartTouch,
      // Only the transparent overlay bar shows a value/indicator → exactly one
      // reading at a time while scrubbing.
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => theme.colorScheme.inverseSurface,
        tooltipBorderRadius: BorderRadius.circular(8),
        getTooltipItems: (touchedSpots) => [
          for (final spot in touchedSpots)
            if (spot.barIndex == touchBarIndex)
              _tooltipItem(context, spot)
            else
              null,
        ],
      ),
      getTouchedSpotIndicator: (barData, indexes) => _indicators(
        barData,
        indexes,
        theme.colorScheme.onSurface.withValues(alpha: 0.35),
      ),
    );
  }

  LineTooltipItem _tooltipItem(BuildContext context, LineBarSpot spot) {
    final theme = Theme.of(context);
    final digits = glucose.unit == GlucoseUnit.mmol ? 1 : 0;
    return LineTooltipItem(
      '${spot.y.toStringAsFixed(digits)} ${glucose.unit.label}',
      TextStyle(
        color: theme.colorScheme.onInverseSurface,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      children: [
        if (anchor != null)
          TextSpan(
            text: '\n${_spotTime(context, spot.x)}',
            style: TextStyle(
              color: theme.colorScheme.onInverseSurface.withValues(alpha: 0.7),
              fontWeight: FontWeight.normal,
              fontSize: 11,
            ),
          ),
      ],
    );
  }

  /// Wall-clock time of a touched spot — `(x - shift)` hours back from [anchor],
  /// the same mapping the X-axis labels use.
  String _spotTime(BuildContext context, double x) {
    final time = anchor!.add(Duration(seconds: ((x - shift) * 3600).round()));
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(time));
  }

  /// fl_chart passes a copyWith of the bar (with showingIndicators set), so
  /// compare by a stable property, not reference: the touch overlay is the only
  /// zero-width bar; colour bars get no indicator.
  List<TouchedSpotIndicatorData?> _indicators(
    LineChartBarData barData,
    List<int> indexes,
    Color lineColor,
  ) {
    if (barData.barWidth != 0) {
      return List<TouchedSpotIndicatorData?>.filled(indexes.length, null);
    }
    return [for (final _ in indexes) _indicator(lineColor)];
  }

  TouchedSpotIndicatorData _indicator(Color lineColor) {
    return TouchedSpotIndicatorData(
      FlLine(color: lineColor, strokeWidth: 1.5, dashArray: const [4, 4]),
      FlDotData(
        getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
          radius: 4,
          color: _zoneForDisplay(spot.y),
          strokeColor: Colors.white,
          strokeWidth: 1.5,
        ),
      ),
    );
  }

  /// Zone colour for a display-unit Y value (used for the touch dot).
  Color _zoneForDisplay(double y) {
    if (y < glucose.toDisplay(glucose.targetLow)) {
      return colors.low;
    }
    if (y > glucose.toDisplay(glucose.targetHigh)) {
      return colors.high;
    }
    return colors.inRange;
  }
}
