import 'package:fl_chart/fl_chart.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/overview/chart/chart_x_axis.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:insulink/src/overview/chart/glucose_y_labels.dart';
import 'package:insulink/src/overview/chart/insulin_bar_chart.dart';

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

  /// Minimal (overview) styling: no grid lines, no Y axis, and the two target
  /// bounds as faint dashed lines. When false the chart keeps the full look — every Y tick and the
  /// horizontal grid lines (the detail/"Glucose" page).
  final bool minimal;

  /// Bottom of the Y axis, in mg/dL. The overview lifts it to ~50 when there's
  /// no lower data (freeing vertical space); the detail page keeps 0.
  final int minYmgdl;

  /// Top of the Y axis, in mg/dL. The overview shrinks it to the data so a low
  /// day doesn't waste vertical space; the detail page keeps the full 300.
  final int maxYmgdl;

  /// The latest reading, drawn as a highlighted dot. Null hides it.
  final FlSpot? highlightSpot;

  /// Whether this chart carries the axis labels.
  ///
  /// False when a second chart is stacked underneath: the labels belong under
  /// the LOWER one, so the two plots touch and the pair reads as one picture
  /// with one axis instead of two charts that happen to be adjacent.
  final bool showBottomTitles;

  double get _minY => glucose.toDisplay(minYmgdl);

  double get _maxY => glucose.toDisplay(maxYmgdl);

  /// The y values the detail chart labels: both target bounds and a reference
  /// line at 250 mg/dL above them.
  List<double> get _yLabels => [
    glucose.toDisplay(glucose.targetLow),
    glucose.toDisplay(glucose.targetHigh),
    glucose.toDisplay(250),
  ];

  @override
  Widget build(BuildContext context) {
    final chart = _chart(context);
    if (minimal) {
      return RepaintBoundary(child: chart);
    }
    return RepaintBoundary(
      child: Stack(
        children: [
          chart,
          Positioned.fill(
            child: IgnorePointer(
              child: GlucoseYLabels(
                values: _yLabels,
                minY: _minY,
                maxY: _maxY,
                stripWidth: InsulinBarChart.axisInset,
                bottomInset: showBottomTitles ? 24 : 0,
                format: _formatY,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chart(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: _minY,
        maxY: _maxY,
        minX: axis.minX,
        maxX: axis.maxX,
        // Clip to the plot: the forecast line runs to its full horizon, which can
        // extend past the (constant-width) window's right edge — without clipping
        // it would draw out over the margin. The preview has no forecast, and
        // its right edge stays open so the end-of-line dot is not cut in half.
        clipData: minimal
            ? const FlClipData(
                top: true,
                bottom: true,
                left: true,
                right: false,
              )
            : const FlClipData.all(),
        gridData: const FlGridData(show: false),
        rangeAnnotations: _targetBand(),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context),
        extraLinesData: _extraLines(context),
        lineTouchData: _touchData(context),
        betweenBarsData: betweenBars,
        lineBarsData: [
          ...bars,
          if (highlightSpot != null) _highlightBar(context),
        ],
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
      // Only reserves the strip; the labels are laid over it by GlucoseYLabels,
      // since 70 and 180 sit on no interval fl_chart could step through.
      rightTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: !minimal,
          reservedSize: InsulinBarChart.axisInset,
          interval: _maxY - _minY,
          getTitlesWidget: (_, _) => const SizedBox.shrink(),
        ),
      ),
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: showBottomTitles,
          reservedSize: 24,
          interval: axis.interval,
          // Drop the fractional min/max edge ticks so only full hours show. The
          // preview keeps its right edge for "now".
          minIncluded: false,
          maxIncluded: minimal,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
            child: _label(context, _bottomText(context, value, meta)),
          ),
        ),
      ),
    );
  }

  /// The preview reads like the redesign: clock times ("4:00") and "now" at the
  /// right edge, with a tick that would crowd "now" left out. The full chart
  /// keeps its hour labels.
  String _bottomText(BuildContext context, double value, TitleMeta meta) {
    if (!minimal) {
      return axis.label(context, value);
    }
    if (value == meta.max) {
      return Locales.string(context, 'overview.chart.axis_now');
    }
    if (meta.max - value < axis.interval * 0.4) {
      return '';
    }
    return axis.clockLabel(value);
  }

  Widget _label(BuildContext context, String text) =>
      Text(text, style: InkText.caption.copyWith(color: context.ink.muted));

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

  /// One dashed line per meal, running on from its label in the strip above.
  List<VerticalLine> _mealLines(Color color) {
    return [for (final marker in mealMarkers) _mealLine(marker, color)];
  }

  VerticalLine _mealLine(({double x, Meal meal}) marker, Color color) {
    return VerticalLine(
      x: marker.x,
      color: color.withValues(alpha: 0.35),
      strokeWidth: 1.5,
      dashArray: const [3, 4],
      // The carb label sits in the strip above the chart (MealLabelStrip),
      // where it can be a pill and never covers the line.
    );
  }

  /// The target range lightly behind the detail chart (range colour at 5 %),
  /// the open preview keeps only its two dashed bounds.
  RangeAnnotations _targetBand() {
    return RangeAnnotations(
      horizontalRangeAnnotations: [
        if (!minimal)
          HorizontalRangeAnnotation(
            y1: glucose.toDisplay(glucose.targetLow),
            y2: glucose.toDisplay(glucose.targetHigh),
            color: colors.inRange.withValues(alpha: 0.05),
          ),
      ],
    );
  }

  HorizontalLine _boundLine(int mgdl, Color color) {
    return HorizontalLine(
      y: glucose.toDisplay(mgdl),
      color: color.withValues(alpha: 0.7),
      strokeWidth: 1,
      dashArray: const [2, 4],
    );
  }

  /// The latest reading as a zone-coloured dot with a ring in the page colour.
  LineChartBarData _highlightBar(BuildContext context) {
    final spot = highlightSpot!;
    final color = _zoneForDisplay(spot.y);
    final ring = context.ink.ground;
    return LineChartBarData(
      spots: [spot],
      barWidth: 0,
      color: Colors.transparent,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
          radius: 6,
          color: color,
          strokeWidth: 3,
          strokeColor: ring,
        ),
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
        context.ink.ground,
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
    Color ringColor,
  ) {
    if (barData.barWidth != 0) {
      return List<TouchedSpotIndicatorData?>.filled(indexes.length, null);
    }
    return [
      for (final _ in indexes)
        _indicator(lineColor, predictionColor, ringColor),
    ];
  }

  TouchedSpotIndicatorData _indicator(
    Color lineColor,
    Color predictionColor,
    Color ringColor,
  ) {
    return TouchedSpotIndicatorData(
      FlLine(color: lineColor, strokeWidth: 1.5, dashArray: const [4, 4]),
      FlDotData(
        // Forecast points (x > shift) get the neutral prediction grey, not a
        // glucose-zone colour — the estimate isn't a measured value.
        getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
          radius: 4,
          color: spot.x > axis.shift
              ? predictionColor
              : _zoneForDisplay(spot.y),
          strokeColor: ringColor,
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
