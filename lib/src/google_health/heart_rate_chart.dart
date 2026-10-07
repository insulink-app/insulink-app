import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/heart_rate_chart_series.dart';
import 'package:insulink/src/google_health/heart_rate_zones.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One heart-rate sample.
typedef HrSample = ({DateTime at, int bpm});

/// The pulse curve between [leftX] and [rightX], hours relative to
/// [wholeHour]: accent below the "elevated" threshold, violet from there on,
/// the threshold dashed. One finger scrubs a single sample; the page around
/// it zooms and pans the window.
///
/// The transparent overlay bar owns touch, so a scrub snaps to one sample
/// rather than to each zone bar (which share the crossing points), and only
/// it draws a touch dot. The y range spans at least 40 bpm so a calm day is
/// not squashed flat.
class HeartRateChart extends StatelessWidget {
  const HeartRateChart({
    super.key,
    required this.samples,
    required this.zones,
    required this.wholeHour,
    required this.leftX,
    required this.rightX,
  });

  final List<HrSample> samples;
  final HeartRateZones zones;
  final DateTime wholeHour;
  final double leftX, rightX;

  double get _rangeHours => rightX - leftX;

  /// Chart X of a time: hours relative to [wholeHour] (negative = earlier).
  double _xOf(DateTime at) => at.difference(wholeHour).inSeconds / 3600;

  @override
  Widget build(BuildContext context) {
    return LineChart(_chartData(context, context.ink), duration: Duration.zero);
  }

  /// Target number of points the line is thinned to. Scales inversely with the
  /// window (120 at 24 h, 240 at 12 h, 480 at 6 h): a zoomed-in range has fewer
  /// samples spread over the same width, so a finer curve stays readable.
  int get _maxChartPoints => (120 * 24 / _rangeHours).round().clamp(120, 2000);

  /// Thins the samples to at most [_maxChartPoints] by averaging each equal-width
  /// time bucket, so the curve reads cleanly while keeping its shape. Stats
  /// (Ø/Min/Max) are computed separately over the full data, so no extremes are
  /// lost to the averaging.
  List<FlSpot> _chartSpots() {
    if (samples.length <= _maxChartPoints) {
      return [
        for (final sample in samples)
          FlSpot(_xOf(sample.at), sample.bpm.toDouble()),
      ];
    }
    final bucketHours = (rightX - leftX) / _maxChartPoints;
    final buckets = <int, ({double x, double y, int count})>{};
    for (final sample in samples) {
      final x = _xOf(sample.at);
      final index = (x / bucketHours).floor();
      final current = buckets[index];
      buckets[index] = current == null
          ? (x: x, y: sample.bpm.toDouble(), count: 1)
          : (
              x: current.x + x,
              y: current.y + sample.bpm,
              count: current.count + 1,
            );
    }
    final indices = buckets.keys.toList()..sort();
    return [
      for (final index in indices)
        FlSpot(
          buckets[index]!.x / buckets[index]!.count,
          buckets[index]!.y / buckets[index]!.count,
        ),
    ];
  }

  /// Accent below the elevated threshold, violet from there on: a raised pulse
  /// is not a warning, so neither red nor amber.
  List<Color> _palette(InsulinkColors colors) => [
    colors.accent,
    colors.pulseHigh,
    colors.pulseHigh,
  ];

  LineChartData _chartData(BuildContext context, InsulinkColors colors) {
    final spots = _chartSpots();
    final series = HeartRateChartSeries(
      points: spots,
      zones: zones,
      palette: _palette(colors),
    );
    final bars = series.buildBars();
    final touchBarIndex = bars.length;
    bars.add(
      LineChartBarData(
        spots: series.spots,
        isCurved: true,
        curveSmoothness: 0.15,
        barWidth: 0,
        color: Colors.transparent,
        dotData: const FlDotData(show: false),
      ),
    );
    final ys = spots.map((spot) => spot.y);
    final yMin = (ys.reduce((a, b) => a < b ? a : b) / 10).floor() * 10.0;
    final rawMax = (ys.reduce((a, b) => a > b ? a : b) / 10).ceil() * 10.0;
    final yMax = rawMax - yMin < 40 ? yMin + 40 : rawMax;
    final yInterval = ((yMax - yMin) / 4 / 10).ceil() * 10.0;
    return LineChartData(
      minX: leftX,
      maxX: rightX,
      minY: yMin,
      maxY: yMax,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: yInterval,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: colors.line, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: zones.elevated.toDouble(),
            color: colors.pulseHigh.withValues(alpha: 0.7),
            strokeWidth: 1,
            dashArray: const [3, 4],
          ),
        ],
      ),
      titlesData: _titles(context, colors, yInterval),
      lineTouchData: _touch(context, colors, touchBarIndex),
      lineBarsData: bars,
    );
  }

  LineTouchData _touch(
    BuildContext context,
    InsulinkColors colors,
    int touchBarIndex,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return LineTouchData(
      getTouchedSpotIndicator: (barData, indexes) {
        if (barData.barWidth != 0) {
          return List<TouchedSpotIndicatorData?>.filled(indexes.length, null);
        }
        return [
          for (final _ in indexes)
            TouchedSpotIndicatorData(
              FlLine(
                color: scheme.onSurface.withValues(alpha: 0.35),
                strokeWidth: 1.5,
                dashArray: const [4, 4],
              ),
              FlDotData(
                getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: _palette(colors)[zones.zoneOf(spot.y)],
                  strokeColor: colors.ground,
                  strokeWidth: 1.5,
                ),
              ),
            ),
        ];
      },
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => scheme.inverseSurface,
        tooltipBorderRadius: BorderRadius.circular(8),
        getTooltipItems: (spots) => [
          for (final spot in spots)
            if (spot.barIndex != touchBarIndex)
              null
            else
              LineTooltipItem(
                '${spot.y.round()} bpm',
                TextStyle(
                  color: scheme.onInverseSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                children: [
                  TextSpan(
                    text: '\n${_clockAt(spot.x)}',
                    style: TextStyle(
                      color: scheme.onInverseSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.normal,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  /// Wall-clock HH:mm of a chart X value (hours relative to [wholeHour]).
  String _clockAt(double x) {
    final time = wholeHour.add(Duration(seconds: (x * 3600).round()));
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  FlTitlesData _titles(
    BuildContext context,
    InsulinkColors colors,
    double yInterval,
  ) {
    final style = InkText.axis.copyWith(fontSize: 12, color: colors.muted);
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: yInterval,
          reservedSize: 36,
          maxIncluded: false,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text('${value.round()}', style: style),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: _rangeHours <= 6 ? 2 : _rangeHours / 4,
          reservedSize: 22,
          minIncluded: false,
          maxIncluded: false,
          getTitlesWidget: (value, meta) {
            final clock = wholeHour.add(Duration(hours: value.round()));
            return SideTitleWidget(
              meta: meta,
              fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
              child: Text(
                Locales.string(
                  context,
                  'overview.chart.hour',
                  params: ['${clock.hour}'],
                ),
                style: style,
              ),
            );
          },
        ),
      ),
    );
  }
}
