import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/google_health/google_health_importer.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:insulink/src/sport/training/km_splits.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:provider/provider.dart';

/// The three plottable metrics, in the fixed order they occupy in the chart's
/// bar list (so a tooltip can map a bar index back to its metric).
enum _Metric { glucose, heart, speed }

/// A single normalised series: the plotted spots (0..1) plus the real values,
/// aligned by index so a hover can show the true reading.
class _Series {
  final List<FlSpot> spots;
  final List<double> raw;

  const _Series(this.spots, this.raw);

  bool get isEmpty => spots.isEmpty;
}

/// Glucose + heart-rate + speed over a training's time span, shown as one chart
/// below the route. All series are normalised to 0..1 (their scales differ
/// wildly), so the Y axis is hidden and the exact values come from the hover
/// tooltip. Scrubbing the chart reports the hovered epoch-ms via [onHoverMs]
/// (null when the pointer leaves) — the parent maps it to a position on the
/// route.
class TrainingMetricsChart extends StatefulWidget {
  const TrainingMetricsChart({
    super.key,
    required this.startMs,
    required this.endMs,
    required this.glucose,
    required this.track,
    required this.onHoverMs,
  });

  final int startMs;
  final int endMs;

  /// Glucose archive over the span, keyed by epoch-minute → mg/dL.
  final Map<int, int> glucose;

  /// The training's GPS track — the speed series is derived from it.
  final List<TrackPoint> track;
  final void Function(int? ms) onHoverMs;

  @override
  State<TrainingMetricsChart> createState() => _TrainingMetricsChartState();
}

class _TrainingMetricsChartState extends State<TrainingMetricsChart>
    with AutomaticKeepAliveClientMixin {
  List<({DateTime at, int bpm})> _heart = const [];
  bool _loading = true;

  /// Metrics the user has toggled off in the legend — hidden from the plot but
  /// still counted as available (their legend chip stays, dimmed).
  final Set<_Metric> _hidden = {};

  // Keep the state alive so scrolling the chart off-screen in the detail
  // ListView doesn't dispose it and re-run _loadHeart() on scroll-back.
  @override
  bool get wantKeepAlive => true;

  /// Whole minute the last haptic tick fired for, so scrubbing buzzes at most
  /// once per minute crossed instead of on every (dense) heart-rate sample.
  int? _lastHapticMinute;

  @override
  void initState() {
    super.initState();
    _loadHeart();
  }

  Future<void> _loadHeart() async {
    final heart = await GoogleHealthImporter().heartRateBetween(
      DateTime.fromMillisecondsSinceEpoch(widget.startMs),
      DateTime.fromMillisecondsSinceEpoch(widget.endMs),
    );
    if (mounted) {
      setState(() {
        _heart = heart;
        _loading = false;
      });
    }
  }

  double _xOf(int ms) => (ms - widget.startMs) / 60000;

  /// Chart X (minutes) of the workout's own end — the extent the axis reference
  /// is anchored to, even when a before/after glucose point extends past it.
  double get _windowMaxX => math.max(1, _xOf(widget.endMs));

  /// Normalises [points] (x, realValue) to 0..1 on Y; a flat series sits at 0.5.
  _Series _normalise(List<({double x, double value})> points) {
    if (points.isEmpty) {
      return const _Series([], []);
    }
    final values = points.map((point) => point.value);
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    final span = max - min;
    return _Series(
      [
        for (final point in points)
          FlSpot(point.x, span == 0 ? 0.5 : (point.value - min) / span),
      ],
      [for (final point in points) point.value],
    );
  }

  _Series get _glucoseSeries => _normalise(_glucosePoints());

  /// Glucose inside the workout window, plus the single reading just before and
  /// just after it — so a short workout with only a point or two still shows a
  /// line with context. Relies on the parent querying a padded window. Entries
  /// are ascending by minute, so [before] keeps the nearest earlier point and
  /// [after] takes the first later one.
  List<({double x, double value})> _glucosePoints() {
    final inside = <({double x, double value})>[];
    ({double x, double value})? before;
    ({double x, double value})? after;
    for (final entry in widget.glucose.entries) {
      final x = _xOf(entry.key * 60000);
      final point = (x: x, value: entry.value.toDouble());
      if (x < 0) {
        before = point;
      } else if (x > _windowMaxX) {
        after ??= point;
      } else {
        inside.add(point);
      }
    }
    return [?before, ...inside, ?after];
  }

  _Series get _heartSeries => _normalise([
    for (final sample in _heart)
      (x: _xOf(sample.at.millisecondsSinceEpoch), value: sample.bpm.toDouble()),
  ]);

  _Series get _speedSeries => _normalise([
    for (final sample in trackSpeeds(widget.track))
      (x: _xOf(sample.tMs), value: sample.kmh),
  ]);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final glucose = _glucoseSeries;
    final heart = _heartSeries;
    final speed = _speedSeries;
    final glucoseColor = scheme.primary;
    final heartColor = scheme.error;
    final speedColor = context.positive;
    // The box is ALWAYS shown (no spinner): the chart area holds the line as soon
    // as there's data, and only once loading is finished with genuinely nothing
    // to show does it swap to the empty-state message.
    final empty = glucose.isEmpty && heart.isEmpty && speed.isEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 16, 16, 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: LocaleText(
              'sport.trainings.metrics',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          if (!empty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  if (!glucose.isEmpty)
                    _legendChip(
                      _Metric.glucose,
                      glucoseColor,
                      'sport.trainings.glucose',
                    ),
                  if (!heart.isEmpty)
                    _legendChip(
                      _Metric.heart,
                      heartColor,
                      'sport.trainings.heart_rate',
                    ),
                  if (!speed.isEmpty)
                    _legendChip(
                      _Metric.speed,
                      speedColor,
                      'sport.trainings.speed',
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 210,
            child: (!_loading && empty)
                ? Center(child: LocaleText('sport.trainings.no_metrics'))
                : LineChart(
                    _data(
                      scheme,
                      _shown(_Metric.glucose, glucose),
                      _shown(_Metric.heart, heart),
                      _shown(_Metric.speed, speed),
                      glucoseColor,
                      heartColor,
                      speedColor,
                      _rangeX,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// The series to actually plot for [metric]: the real one, or an empty series
  /// when the user has toggled it off (keeps the bar index stable so tooltip
  /// mapping doesn't shift).
  _Series _shown(_Metric metric, _Series series) {
    return _hidden.contains(metric) ? const _Series([], []) : series;
  }

  /// A tappable legend entry: tap toggles its metric on the plot. When off, the
  /// dot and label dim and the label is struck through.
  Widget _legendChip(_Metric metric, Color color, String labelKey) {
    final scheme = Theme.of(context).colorScheme;
    final hidden = _hidden.contains(metric);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() {
        if (!_hidden.remove(metric)) {
          _hidden.add(metric);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: hidden ? color.withValues(alpha: 0.3) : color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            LocaleText(
              labelKey,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: hidden ? scheme.onSurface.withValues(alpha: 0.35) : null,
                decoration: hidden ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The X span the chart draws over: the training window itself. The
  /// before/after glucose points sit outside it and are drawn clipped (their line
  /// still enters from the edge), so the axis isn't widened past the activity —
  /// which would leave the shorter heart/speed series looking cut off inside a
  /// mostly-empty window.
  ({double min, double max}) get _rangeX => (min: 0, max: _windowMaxX);

  LineChartData _data(
    ColorScheme scheme,
    _Series glucose,
    _Series heart,
    _Series speed,
    Color glucoseColor,
    Color heartColor,
    Color speedColor,
    ({double min, double max}) rangeX,
  ) {
    return LineChartData(
      minX: rangeX.min,
      maxX: rangeX.max,
      minY: -0.08,
      maxY: 1.08,
      // Clip to the plot rect so a curved line between few points (short
      // workout) can't overshoot outside the box.
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 0.5,
        getDrawingHorizontalLine: (_) => FlLine(
          color: scheme.onSurface.withValues(alpha: 0.06),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: _titles(scheme, rangeX),
      lineTouchData: _touch(scheme, glucose, heart, speed),
      lineBarsData: [
        _bar(glucose, glucoseColor, fill: true),
        _bar(heart, heartColor, fill: false),
        _bar(speed, speedColor, fill: false),
      ],
    );
  }

  LineChartBarData _bar(_Series series, Color color, {required bool fill}) {
    return LineChartBarData(
      spots: series.spots,
      isCurved: true,
      curveSmoothness: 0.25,
      preventCurveOverShooting: true,
      barWidth: 3,
      color: color,
      isStrokeCapRound: true,
      isStrokeJoinRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: fill,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
        ),
      ),
    );
  }

  FlTitlesData _titles(ColorScheme scheme, ({double min, double max}) rangeX) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: math.max(1, (rangeX.max - rangeX.min) / 4),
          reservedSize: 22,
          minIncluded: false,
          maxIncluded: false,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(
              _clockAt(value),
              style: TextStyle(
                fontSize: 9,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  LineTouchData _touch(
    ColorScheme scheme,
    _Series glucose,
    _Series heart,
    _Series speed,
  ) {
    // The hovered point reads as a neutral marker, not the series colour: white
    // on dark, black on light, ringed by its opposite so it stays visible.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dotColor = isDark ? Colors.white : Colors.black;
    final dotStroke = isDark ? Colors.black : Colors.white;
    return LineTouchData(
      // Measure nearness by horizontal distance only, with no threshold, so a
      // hover always picks the nearest point on EVERY line at that time — the
      // tooltip shows all metrics at once, not just the line under the cursor.
      distanceCalculator: (touchPoint, spotPixel) =>
          (touchPoint.dx - spotPixel.dx).abs(),
      touchSpotThreshold: double.infinity,
      touchCallback: (event, response) {
        final spots = response?.lineBarSpots;
        if (!event.isInterestedForInteractions ||
            spots == null ||
            spots.isEmpty) {
          widget.onHoverMs(null);
          _lastHapticMinute = null;
          return;
        }
        final spot = spots.first;
        final minute = spot.x.round();
        if (minute != _lastHapticMinute) {
          _lastHapticMinute = minute;
          HapticFeedback.selectionClick();
        }
        widget.onHoverMs(widget.startMs + (spot.x * 60000).round());
      },
      getTouchedSpotIndicator: (barData, indexes) => [
        for (final _ in indexes)
          TouchedSpotIndicatorData(
            FlLine(
              color: scheme.onSurface.withValues(alpha: 0.3),
              strokeWidth: 1.5,
              dashArray: const [4, 4],
            ),
            FlDotData(
              getDotPainter: (spot, _, bar, _) => FlDotCirclePainter(
                radius: 4,
                color: dotColor,
                strokeColor: dotStroke,
                strokeWidth: 1.5,
              ),
            ),
          ),
      ],
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => scheme.inverseSurface,
        tooltipBorderRadius: BorderRadius.circular(8),
        getTooltipItems: (spots) => [
          for (var index = 0; index < spots.length; index++)
            _tooltipItem(
              context,
              scheme,
              spots[index],
              glucose,
              heart,
              speed,
              showTime: index == spots.length - 1,
            ),
        ],
      ),
    );
  }

  LineTooltipItem _tooltipItem(
    BuildContext context,
    ColorScheme scheme,
    LineBarSpot spot,
    _Series glucose,
    _Series heart,
    _Series speed, {
    required bool showTime,
  }) {
    final series = switch (spot.barIndex) {
      0 => glucose,
      1 => heart,
      _ => speed,
    };
    final raw = series.raw[spot.spotIndex];
    final text = switch (spot.barIndex) {
      0 => context.read<ProfileGlucoseState>().formatWithUnit(raw.round()),
      1 => '${raw.round()} bpm',
      _ => formatSpeed(raw),
    };
    final color = switch (spot.barIndex) {
      0 => scheme.onInverseSurface,
      1 => scheme.error,
      _ => context.positive,
    };
    return LineTooltipItem(
      text,
      TextStyle(
        color: color,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      children: showTime
          ? [
              TextSpan(
                text: '\n${_clockAt(spot.x)}',
                style: TextStyle(
                  color: scheme.onInverseSurface.withValues(alpha: 0.7),
                  fontWeight: FontWeight.normal,
                  fontSize: 11,
                ),
              ),
            ]
          : null,
    );
  }

  /// Wall-clock HH:mm for a chart X value (minutes since the training start).
  String _clockAt(double x) {
    final time = DateTime.fromMillisecondsSinceEpoch(
      widget.startMs + (x * 60000).round(),
    );
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}
