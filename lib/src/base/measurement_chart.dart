import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.decimals = 1,
  });

  final List<MeasurementPoint> points;

  /// Rendered after every value ('kg', '%'). Empty is fine for a bare number.
  final String unit;

  /// Target value drawn as a labelled horizontal line, and folded into the Y
  /// range so the line is always visible.
  final double? goal;

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
      '${value.toStringAsFixed(widget.decimals)}${widget.unit.isEmpty ? '' : ' ${widget.unit}'}';

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final onSurface = Theme.of(context).colorScheme.onSurface;
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
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context, minX, maxX, span),
        extraLinesData: _goalLine(context, goal),
        lineTouchData: _touchData(context),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            preventCurveOverShooting: true,
            barWidth: 2.5,
            color: onSurface.withValues(alpha: 0.85),
            dotData: FlDotData(show: points.length == 1),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  /// Dashed target line with the goal value labelled above it.
  ExtraLinesData _goalLine(BuildContext context, double? goal) {
    if (goal == null) {
      return const ExtraLinesData();
    }
    final accent = Theme.of(context).colorScheme.primary;
    return ExtraLinesData(
      horizontalLines: [
        HorizontalLine(
          y: goal,
          color: accent.withValues(alpha: 0.7),
          strokeWidth: 1.5,
          label: HorizontalLineLabel(
            show: true,
            alignment: Alignment.bottomLeft,
            style: TextStyle(
              fontSize: 10,
              color: accent,
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
    final locale = MaterialLocalizations.of(context);
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
                locale.formatShortDate(date),
                style: TextStyle(
                  fontSize: 9,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
