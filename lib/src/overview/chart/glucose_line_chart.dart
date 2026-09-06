import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/overview/chart/chart_x_axis.dart';
import 'package:insulink/src/overview/chart/meal_label_rows.dart';
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
    required this.axis,
    required this.glucose,
    required this.colors,
    required this.onChartTouch,
    this.interactive = true,
    this.minimal = false,
    this.minYmgdl = 0,
    this.maxYmgdl = 300,
    this.highlightSpot,
    this.pulse = 0,
    this.showBottomTitles = true,
    this.betweenBars = const [],
    this.mealMarkers = const [],
  });

  /// Logged meals to mark on the chart, each at its x (shifted hours). Drawn as
  /// dashed vertical lines with the carb amount; the tappable dots that open a
  /// meal live on a bar the caller adds to [bars]. Empty unless the meal overlay
  /// is on (the detail page's toggle).
  final List<({double x, Meal meal})> mealMarkers;

  /// Fills between two of [bars], by index — the forecast's uncertainty band.
  /// Empty unless the band overlay is on. Indexes are resolved by the caller,
  /// which owns [bars]' order, so [_highlightBar] must stay APPENDED last or the
  /// indexes would shift out from under it.
  final List<BetweenBarsData> betweenBars;

  final List<LineChartBarData> bars;

  /// Index of the transparent overlay bar that owns touch.
  final int touchBarIndex;

  /// The shared time axis: what the window covers, and how an x maps to a clock.
  final ChartXAxis axis;

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

  /// Whether this chart carries the axis labels.
  ///
  /// False when a second chart is stacked underneath: the labels belong under
  /// the LOWER one, so the two plots touch and the pair reads as one picture
  /// with one axis instead of two charts that happen to be adjacent.
  final bool showBottomTitles;

  double get _minY => glucose.toDisplay(minYmgdl);

  double get _maxY => glucose.toDisplay(maxYmgdl);

  /// Whole-unit gridlines/ticks that read cleanly in either unit.
  double get _yInterval => glucose.unit == GlucoseUnit.mmol ? 3.0 : 50.0;

  @override
  Widget build(BuildContext context) {
    // Isolate the chart's canvas: the pulsing latest-reading marker repaints at
    // frame rate, and the surrounding page (scrolling list, headline value) has
    // no reason to repaint with it. Without this the marker's every frame dirties
    // the whole overview.
    return RepaintBoundary(
      child: LineChart(
        LineChartData(
          minY: _minY,
          maxY: _maxY,
          minX: axis.minX,
          maxX: axis.maxX,
          // Clip to the plot: the forecast line runs to its full horizon, which can
          // extend past the (constant-width) window's right edge — without clipping
          // it would draw out over the margin.
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: !minimal,
            drawVerticalLine: false,
            horizontalInterval: _yInterval,
          ),
          borderData: FlBorderData(show: false),
          titlesData: _titles(context),
          extraLinesData: _extraLines(context),
          lineTouchData: _touchData(context),
          betweenBarsData: betweenBars,
          lineBarsData: [...bars, if (highlightSpot != null) _highlightBar()],
        ),
        // No implicit morph animation: the number of zone bars changes between
        // states, so fl_chart would interpolate between mismatched structures —
        // which looked broken on load/update. Render each state directly.
        duration: Duration.zero,
      ),
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
          showTitles: showBottomTitles,
          reservedSize: 24,
          interval: axis.interval,
          // Drop the fractional min/max edge ticks so only full hours show.
          minIncluded: false,
          maxIncluded: false,
          getTitlesWidget: (value, _) =>
              _label(context, axis.label(context, value)),
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

  /// The two target-range bound lines plus, when the meal overlay is on, a
  /// dashed vertical line per logged meal labelled with its carbs. The target
  /// values are labelled on the Y axis (see `_leftLabel`), so those lines stay
  /// label-free.
  ExtraLinesData _extraLines(BuildContext context) {
    final mealColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return ExtraLinesData(
      horizontalLines: [
        _boundLine(glucose.targetLow, colors.low),
        _boundLine(glucose.targetHigh, colors.high),
      ],
      verticalLines: _mealLines(mealColor),
    );
  }

  /// One dashed line per meal, with the labels of meals logged close together
  /// stacked downward so they cannot print over each other
  /// ([MealLabelRows]).
  List<VerticalLine> _mealLines(Color color) {
    final rows = MealLabelRows(spanX: axis.maxX - axis.minX)
        .assign([for (final marker in mealMarkers) marker.x]);
    return [
      for (var index = 0; index < mealMarkers.length; index++)
        _mealLine(mealMarkers[index], color, rows[index]),
    ];
  }

  /// [row] is how many label heights this one is dropped by, so a cluster reads
  /// as a staircase instead of a smear.
  VerticalLine _mealLine(
    ({double x, Meal meal}) marker,
    Color color,
    int row,
  ) {
    return VerticalLine(
      x: marker.x,
      color: color.withValues(alpha: 0.35),
      strokeWidth: 1.5,
      dashArray: const [3, 4],
      // Anchored at the top, but pushed to the RIGHT of the line so the carb
      // amount sits beside it — the dashed line never runs through the text.
      label: VerticalLineLabel(
        show: true,
        alignment: Alignment.topRight,
        padding: EdgeInsets.only(left: 3, top: row * _mealLabelHeight),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
        labelResolver: (_) => '${marker.meal.carbs.toStringAsFixed(0)}g',
      ),
    );
  }

  /// One label's line height at font size 9, which is what a stacked label drops
  /// by. A shade more than the glyphs need, so two rows are visibly two rows.
  static const double _mealLabelHeight = 11;

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
    final prefix = spot.x > axis.shift ? '~' : '';
    return LineTooltipItem(
      '$prefix${spot.y.toStringAsFixed(digits)} ${glucose.unit.label}',
      TextStyle(
        color: theme.colorScheme.onInverseSurface,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      children: [
        if (axis.anchor != null)
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

  /// Wall-clock time of a touched spot, the same mapping the axis labels use.
  String _spotTime(BuildContext context, double x) {
    final time = axis.anchor!.add(
      Duration(seconds: ((x - axis.shift) * 3600).round()),
    );
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
          color: spot.x > axis.shift ? predictionColor : _zoneForDisplay(spot.y),
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
