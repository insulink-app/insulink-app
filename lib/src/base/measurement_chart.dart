import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:intl/intl.dart';

/// One plotted measurement: when it was taken and what it read.
typedef MeasurementPoint = ({int atEpochMs, double value});

/// A dated decimal measurement over time as a line — X = timestamp (true spacing
/// for uneven gaps), Y scaled automatically with a little margin. Expects
/// [points] already filtered by time window and sorted ascending. A single point
/// is drawn as a dot.
///
/// Scrubbing/hovering shows a value+date tooltip with an indicator dot and a
/// haptic tick per point, mirroring the overview glucose chart.
///
/// Shared by the weight history and the HbA1c history: the two differ only in
/// their unit and whether they carry a goal line, so the chart takes both as
/// parameters rather than existing twice.
class MeasurementChart extends StatefulWidget {
  const MeasurementChart({
    super.key,
    required this.points,
    required this.unit,
    this.goal,
    this.average,
    this.decimals = 1,
  });

  final List<MeasurementPoint> points;

  /// Rendered after every value ('kg', '%'). Empty is fine for a bare number.
  final String unit;

  /// Target value drawn as a labelled horizontal line, and folded into the Y
  /// range so the line is always visible.
  final double? goal;

  /// Drawn as a dashed line across the chart; null draws none.
  final double? average;

  /// Decimal places for values in the tooltip and the goal label.
  final int decimals;

  @override
  State<MeasurementChart> createState() => _MeasurementChartState();
}

class _MeasurementChartState extends State<MeasurementChart> {
  /// Spot index under the finger on the last touch event, so we buzz once per
  /// point as the finger moves across (and reset when it lifts off).
  int? _lastTouchedIndex;

  String _label(double value) =>
      '${sportDecimal(value, widget.decimals)}${widget.unit.isEmpty ? '' : ' ${widget.unit}'}';

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final colors = context.ink;
    final spots = [
      for (final point in points)
        FlSpot(point.atEpochMs.toDouble(), point.value),
    ];
    final goal = widget.goal;
    final values = [for (final point in points) point.value, ?goal];
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final span = maxValue - minValue;
    final pad = span < 1 ? 1.0 : span * 0.2;
    final minX = points.first.atEpochMs.toDouble();
    final maxX = points.last.atEpochMs.toDouble();

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX == minX ? minX + 1 : maxX,
        minY: minValue - pad,
        maxY: maxValue + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.panelRaised, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context, minX, maxX, span),
        extraLinesData: _lines(context, goal),
        lineTouchData: _touchData(context),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            preventCurveOverShooting: true,
            barWidth: 2.5,
            color: colors.text,
            dotData: FlDotData(
              checkToShowDot: (spot, bar) => spot.x == bar.spots.last.x,
              getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                radius: 5,
                color: colors.text,
                strokeColor: colors.panel,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  /// The average as a dashed accent line (when given) and the target as a
  /// solid muted line with the goal value labelled above it.
  ExtraLinesData _lines(BuildContext context, double? goal) {
    final colors = context.ink;
    final accent = colors.accent;
    final average = widget.average;
    return ExtraLinesData(
      horizontalLines: [
        if (average != null)
          HorizontalLine(
            y: average,
            color: accent,
            strokeWidth: 1.5,
            dashArray: const [4, 4],
          ),
        if (goal != null)
          HorizontalLine(
            y: goal,
            color: colors.muted,
            strokeWidth: 1.5,
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.bottomLeft,
              style: TextStyle(
                fontSize: 10,
                color: colors.muted,
                fontWeight: FontWeight.w600,
              ),
              labelResolver: (_) => _label(goal),
            ),
          ),
      ],
    );
  }

  LineTouchData _touchData(BuildContext context) {
    final theme = Theme.of(context);
    return LineTouchData(
      touchCallback: _onTouch,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => theme.colorScheme.inverseSurface,
        tooltipBorderRadius: BorderRadius.circular(8),
        getTooltipItems: (spots) => [
          for (final spot in spots) _tooltipItem(context, spot),
        ],
      ),
      getTouchedSpotIndicator: (barData, indexes) => [
        for (final _ in indexes)
          TouchedSpotIndicatorData(
            FlLine(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              strokeWidth: 1.5,
              dashArray: const [4, 4],
            ),
            FlDotData(
              getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                radius: 4,
                color: theme.colorScheme.onSurface,
                strokeColor: theme.colorScheme.surface,
                strokeWidth: 1.5,
              ),
            ),
          ),
      ],
    );
  }

  LineTooltipItem _tooltipItem(BuildContext context, LineBarSpot spot) {
    final theme = Theme.of(context);
    final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
    return LineTooltipItem(
      _label(spot.y),
      TextStyle(
        color: theme.colorScheme.onInverseSurface,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      children: [
        TextSpan(
          text: '\n${MaterialLocalizations.of(context).formatShortDate(date)}',
          style: TextStyle(
            color: theme.colorScheme.onInverseSurface.withValues(alpha: 0.7),
            fontWeight: FontWeight.normal,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  /// Light haptic tick when the highlighted point changes while scrubbing.
  void _onTouch(FlTouchEvent event, LineTouchResponse? response) {
    final spots = response?.lineBarSpots;
    if (!event.isInterestedForInteractions || spots == null || spots.isEmpty) {
      _lastTouchedIndex = null;
      return;
    }
    if (spots.first.spotIndex != _lastTouchedIndex) {
      _lastTouchedIndex = spots.first.spotIndex;
      HapticFeedback.selectionClick();
    }
  }

  /// Only the first and last date on the X axis; the Y axis drops to whole
  /// numbers once the plotted span is wide enough for them to differ (weight),
  /// and keeps a decimal for a narrow one (HbA1c, where every label would
  /// otherwise read the same).
  FlTitlesData _titles(
    BuildContext context,
    double minX,
    double maxX,
    double span,
  ) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: maxX > minX ? (maxX - minX) : null,
          getTitlesWidget: (value, meta) {
            if (value > minX && value < maxX) {
              return const SizedBox.shrink();
            }
            final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
            return SideTitleWidget(
              meta: meta,
              fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
              child: Text(
                DateFormat.MMMd(
                  Localizations.localeOf(context).toLanguageTag(),
                ).format(date),
                style: InkText.axis.copyWith(
                  fontSize: 12,
                  color: context.ink.muted,
                ),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(
              value.toStringAsFixed(span < 5 ? 1 : 0),
              style: InkText.axis.copyWith(
                fontSize: 12,
                color: context.ink.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
