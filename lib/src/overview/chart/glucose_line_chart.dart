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
    this.interactive = true,
    this.minimal = false,
    this.minYmgdl = 0,
    this.maxYmgdl = 300,
    this.highlightSpot,
    this.pulse = 0,
    this.futureHours = 0,
    this.panHours = 0,
    this.betweenBars = const [],
  });

  /// Fills between two of [bars], by index — the forecast's uncertainty band.
  /// Empty unless the band overlay is on. Indexes are resolved by the caller,
  /// which owns [bars]' order, so [_highlightBar] must stay APPENDED last or the
  /// indexes would shift out from under it.
  final List<BetweenBarsData> betweenBars;

  /// Hours the visible window is scrolled BACK from the latest reading (0 = the
  /// live window). Shifts [minX]/[maxX] left without moving the x=0 anchor, so
  /// the clock-time labels stay correct for the earlier interval.
  final double panHours;

  final List<LineChartBarData> bars;

  /// Extra hours drawn to the RIGHT of the latest reading, for the prediction
  /// overlay (0 when there's no forecast). Widens [maxX] past [shift] so the
  /// future dashed line isn't clipped.
  final double futureHours;

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

  /// When false the chart is a static preview (no scrub tooltip/haptics), so an
  /// outer tap handler can open the full-screen detail page instead.
  final bool interactive;

  /// Minimal (overview) styling: no grid lines and only the two target bounds on
  /// the Y axis. When false the chart keeps the full look — every Y tick and the
  /// horizontal grid lines (the detail/"Glucose" page).
  final bool minimal;

  /// Bottom of the Y axis, in mg/dL. The overview lifts it to ~50 when there's
  /// no lower data (freeing vertical space); the detail page keeps 0.
  final int minYmgdl;

  /// Top of the Y axis, in mg/dL. The overview shrinks it to the data so a low
  /// day doesn't waste vertical space; the detail page keeps the full 300.
  final int maxYmgdl;

  /// The latest reading, drawn as a pulsing highlighted dot. Null hides it.
  final FlSpot? highlightSpot;

  /// Pulse phase 0..1 driving the highlight dot's halo (animated by the parent).
  final double pulse;

  double get _minY => glucose.toDisplay(minYmgdl);

  double get _maxY => glucose.toDisplay(maxYmgdl);

  /// Whole-unit gridlines/ticks that read cleanly in either unit.
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
        minY: _minY,
        maxY: _maxY,
        minX: shift - rangeHours - panHours,
        maxX: shift + futureHours - panHours,
        gridData: FlGridData(
          show: !minimal,
          drawVerticalLine: false,
          horizontalInterval: _yInterval,
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context),
        extraLinesData: _targetBand(),
        lineTouchData: _touchData(context),
        betweenBarsData: betweenBars,
        lineBarsData: [...bars, if (highlightSpot != null) _highlightBar()],
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
          reservedSize: 24,
          interval: minimal ? _minimalTick : _yInterval,
          getTitlesWidget: (value, _) => _leftLabel(context, value),
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
          getTitlesWidget: (value, _) =>
              _label(context, _xLabel(context, value)),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 10,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  /// Coarse tick step for the minimal axis — kept large (few ticks per frame,
  /// since the pulse re-lays-out the chart) while still landing a tick near each
  /// target bound.
  double get _minimalTick => glucose.unit == GlucoseUnit.mmol ? 0.5 : 10.0;

  /// Left-axis Y label. In minimal mode only the two target bounds are labelled
  /// (at their nearest tick, showing the true threshold value); the full chart
  /// labels every tick.
  Widget _leftLabel(BuildContext context, double value) {
    if (!minimal) {
      return _label(context, _formatY(value));
    }
    final target = _targetForTick(value);
    if (target == null) {
      return const SizedBox.shrink();
    }
    return _label(context, glucose.format(target));
  }

  /// The target bound (mg/dL) whose nearest axis tick is [value], or null.
  int? _targetForTick(double value) {
    for (final target in [glucose.targetLow, glucose.targetHigh]) {
      final nearest =
          (glucose.toDisplay(target) / _minimalTick).round() * _minimalTick;
      if ((value - nearest).abs() < _minimalTick / 2) {
        return target;
      }
    }
    return null;
  }

  String _formatY(double value) {
    if (glucose.unit == GlucoseUnit.mgdl) {
      return '${value.round()}';
    }
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

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

  /// User-configurable target range band (the two bound lines). The values are
  /// labelled on the Y axis (see `_leftLabel`), so the lines stay label-free.
  ExtraLinesData _targetBand() {
    return ExtraLinesData(
      horizontalLines: [
        _boundLine(glucose.targetLow, colors.low),
        _boundLine(glucose.targetHigh, colors.high),
      ],
    );
  }

  HorizontalLine _boundLine(int mgdl, Color color) {
    return HorizontalLine(
      y: glucose.toDisplay(mgdl),
      color: color.withValues(alpha: 0.4),
      strokeWidth: 1,
    );
  }

  /// The latest reading as a solid zone-coloured core emitting expanding,
  /// fading rings (a radar-style ripple driven by [pulse]).
  LineChartBarData _highlightBar() {
    final spot = highlightSpot!;
    final color = _zoneForDisplay(spot.y);
    return LineChartBarData(
      spots: [spot],
      barWidth: 0,
      color: Colors.transparent,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, _, _, _) =>
            RippleDotPainter(color: color, phase: pulse),
      ),
    );
  }

  LineTouchData _touchData(BuildContext context) {
    final theme = Theme.of(context);
    return LineTouchData(
      enabled: interactive,
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
        HSLColor.fromColor(
          theme.colorScheme.onSurface,
        ).withLightness(0.6).toColor(),
      ),
    );
  }

  LineTooltipItem _tooltipItem(BuildContext context, LineBarSpot spot) {
    final theme = Theme.of(context);
    final digits = glucose.unit == GlucoseUnit.mmol ? 1 : 0;
    // Points past the latest reading (x > shift) are the forecast — mark the
    // value as an estimate with a leading "~".
    final prefix = spot.x > shift ? '~' : '';
    return LineTooltipItem(
      '$prefix${spot.y.toStringAsFixed(digits)} ${glucose.unit.label}',
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
    Color predictionColor,
  ) {
    if (barData.barWidth != 0) {
      return List<TouchedSpotIndicatorData?>.filled(indexes.length, null);
    }
    return [for (final _ in indexes) _indicator(lineColor, predictionColor)];
  }

  TouchedSpotIndicatorData _indicator(Color lineColor, Color predictionColor) {
    return TouchedSpotIndicatorData(
      FlLine(color: lineColor, strokeWidth: 1.5, dashArray: const [4, 4]),
      FlDotData(
        // Forecast points (x > shift) get the neutral prediction grey, not a
        // glucose-zone colour — the estimate isn't a measured value.
        getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
          radius: 4,
          color: spot.x > shift ? predictionColor : _zoneForDisplay(spot.y),
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

/// Draws the latest-reading marker: a solid core with a single filled wave that
/// grows out from the centre and fades as it expands (one wave at a time).
/// [phase] is the animation clock in 0..1 (sawtooth, not reversing).
class RippleDotPainter extends FlDotPainter {
  const RippleDotPainter({required this.color, required this.phase});

  final Color color;
  final double phase;

  static const double _coreRadius = 5;
  static const double _maxRadius = 22;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset center) {
    final wave = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: (1 - phase) * 0.4);
    canvas.drawCircle(center, phase * _maxRadius, wave);
    canvas.drawCircle(center, _coreRadius, Paint()..color = color);
  }

  @override
  Size getSize(FlSpot spot) => const Size(_maxRadius * 2, _maxRadius * 2);

  @override
  Color get mainColor => color;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) {
    if (a is RippleDotPainter && b is RippleDotPainter) {
      return RippleDotPainter(
        color: Color.lerp(a.color, b.color, t) ?? b.color,
        phase: b.phase,
      );
    }
    return b;
  }

  @override
  List<Object?> get props => [color, phase];
}
