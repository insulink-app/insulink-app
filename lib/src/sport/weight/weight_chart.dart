import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/sport/sport_models.dart';

/// Weight over time as a line — X = timestamp (true spacing for uneven gaps), Y
/// scaled automatically with a little margin. Expects [weights] already filtered
/// by time window and sorted ascending. A single point is drawn as a dot.
///
/// Scrubbing/hovering shows a value+date tooltip with an indicator dot and a
/// haptic tick per point, mirroring the overview glucose chart.
class WeightChart extends StatefulWidget {
  const WeightChart({super.key, required this.weights});

  final List<WeightEntry> weights;

  @override
  State<WeightChart> createState() => _WeightChartState();
}

class _WeightChartState extends State<WeightChart> {
  /// Spot index under the finger on the last touch event, so we buzz once per
  /// point as the finger moves across (and reset when it lifts off).
  int? _lastTouchedIndex;

  @override
  Widget build(BuildContext context) {
    final weights = widget.weights;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final spots = [
      for (final entry in weights) FlSpot(entry.atEpochMs.toDouble(), entry.kg),
    ];
    final values = weights.map((entry) => entry.kg);
    final minKg = values.reduce((a, b) => a < b ? a : b);
    final maxKg = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxKg - minKg) < 1 ? 1.0 : (maxKg - minKg) * 0.2;
    final minX = weights.first.atEpochMs.toDouble();
    final maxX = weights.last.atEpochMs.toDouble();

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX == minX ? minX + 1 : maxX,
        minY: minKg - pad,
        maxY: maxKg + pad,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context, onSurface, minX, maxX),
        lineTouchData: _touchData(context),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            preventCurveOverShooting: true,
            barWidth: 2.5,
            color: onSurface.withValues(alpha: 0.85),
            dotData: FlDotData(show: weights.length == 1),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  LineTouchData _touchData(BuildContext context) {
    final theme = Theme.of(context);
    return LineTouchData(
      touchCallback: _onTouch,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => theme.colorScheme.inverseSurface,
        tooltipBorderRadius: BorderRadius.circular(8),
        getTooltipItems: (spots) =>
            [for (final spot in spots) _tooltipItem(context, spot)],
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
      '${spot.y.toStringAsFixed(1)} kg',
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

  FlTitlesData _titles(
    BuildContext context,
    Color onSurface,
    double minX,
    double maxX,
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
                style: const TextStyle(fontSize: 9, color: Colors.grey),
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
              value.toStringAsFixed(0),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }
}
