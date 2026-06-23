import 'dart:collection';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// fl_chart line graph of glucose vs. time (hours, 0 = latest reading).
class OverviewChart extends StatefulWidget {
  const OverviewChart({super.key, required this.byTime, this.sensorStart});

  final SplayTreeMap<int, int> byTime;

  /// Wall-clock time the session started (`secsSinceStart == 0`). Lets the X
  /// axis show real clock times instead of hours-ago offsets.
  final DateTime? sensorStart;

  @override
  State<OverviewChart> createState() => _OverviewChartState();
}

class _OverviewChartState extends State<OverviewChart> {
  static const _kRangeKey = 'chart_range_hours';
  static const _storage = FlutterSecureStorage();

  /// Visible time window in hours (selectable: 6 / 12 / 24). Persisted.
  int _rangeHours = 24;

  @override
  void initState() {
    super.initState();
    _loadRange();
  }

  Future<void> _loadRange() async {
    final h = int.tryParse(await _storage.read(key: _kRangeKey) ?? '');
    if (mounted && (h == 6 || h == 12 || h == 24)) {
      setState(() => _rangeHours = h!);
    }
  }

  void _setRange(int hours) {
    setState(() => _rangeHours = hours);
    _storage.write(key: _kRangeKey, value: '$hours');
  }

  /// Index of the transparent overlay bar that owns touch (so the haptic and
  /// tooltip ignore the per-zone colour bars + interpolated crossing points).
  int _touchBarIndex = 0;

  /// Spot index under the finger on the last touch event, so we only buzz once
  /// per data point as the finger moves across (and reset when it lifts off).
  int? _lastTouchedIndex;

  /// Light haptic tick when the highlighted point changes while scrubbing.
  void _onChartTouch(FlTouchEvent event, LineTouchResponse? response) {
    final spots = response?.lineBarSpots;
    if (!event.isInterestedForInteractions || spots == null || spots.isEmpty) {
      _lastTouchedIndex = null;
      return;
    }
    // Use the overlay (real-reading) bar's spot, so movement is tracked per
    // actual reading rather than per colour segment.
    LineBarSpot? touch;
    for (final sp in spots) {
      if (sp.barIndex == _touchBarIndex) {
        touch = sp;
        break;
      }
    }
    final index = (touch ?? spots.first).spotIndex;
    if (index != _lastTouchedIndex) {
      _lastTouchedIndex = index;
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ProfileGlucoseState>();
    final theme = Theme.of(context);
    final gc = theme.extension<GlucoseColors>()!;
    final byTime = widget.byTime;
    if (byTime.isEmpty) {
      return Center(child: LocaleText('overview.chart.empty'));
    }
    final entries = byTime.entries.toList();
    final latestSecs = entries.last.key;
    // Wall-clock time at x == 0 (the latest reading), to label the X axis with
    // real times. x is hours relative to this, so wall(x) = anchor + x hours.
    final anchor = widget.sensorStart?.add(Duration(seconds: latestSecs));
    // Phase-shift X so full wall-clock hours land on integer x values (the axis
    // ticks): shift = the fractional-hour part of the latest reading's time.
    // x == shift is the latest reading; x == 0, -1, -2 … are full clock hours.
    final shift = anchor == null
        ? 0.0
        : (anchor.minute * 60 + anchor.second) / 3600.0;
    // Selected time window (last N hours), even if more history is cached.
    final rangeHours = _rangeHours;
    final cutoff = latestSecs - rangeHours * 3600;
    final tLow = s.targetLow;
    final tHigh = s.targetHigh;
    Color zoneOf(int v) =>
        v < tLow ? gc.low : (v > tHigh ? gc.high : gc.inRange);
    // Y values are converted to the chosen display unit; X stays hours-ago.
    // Each point gets a zone colour (red below target, amber above, green in
    // range). Where two readings straddle a target line, an interpolated point
    // is inserted EXACTLY at the crossing so the colour flips at the line — not
    // at the first out-of-range reading (which turned the curve red too early).
    final spots = <FlSpot>[];
    final zoneColors = <Color>[];
    // Real readings only (no interpolated crossings) — drives touch/tooltip.
    final realSpots = <FlSpot>[];
    int? prevVal;
    double? prevX;
    for (final e in entries) {
      if (e.key < cutoff) {
        continue;
      }
      final x = (e.key - latestSecs) / 3600.0 + shift;
      final v = e.value;
      if (prevVal != null) {
        final pv = prevVal;
        final px = prevX!;
        final crossings = <MapEntry<double, int>>[];
        for (final t in [tLow, tHigh]) {
          if ((pv < t) != (v < t)) {
            final frac = (t - pv) / (v - pv);
            if (frac > 0 && frac < 1) {
              crossings.add(MapEntry(px + frac * (x - px), t));
            }
          }
        }
        crossings.sort((a, b) => a.key.compareTo(b.key));
        for (final c in crossings) {
          // A crossing sits on the in-range edge of the band.
          spots.add(FlSpot(c.key, s.toDisplay(c.value)));
          zoneColors.add(gc.inRange);
        }
      }
      final spot = FlSpot(x, s.toDisplay(v));
      spots.add(spot);
      realSpots.add(spot);
      zoneColors.add(zoneOf(v));
      prevVal = v;
      prevX = x;
    }
    final minX = shift - rangeHours;
    final showDots = spots.length < 60;
    // Split the line into solid-colour segments by zone instead of blending a
    // gradient across it: on steep parts the blend showed green and red running
    // side by side (looked like two parallel lines). Each contiguous run of
    // same-zone segments becomes its own bar, meeting the next at a shared point.
    final bars = <LineChartBarData>[];
    if (spots.length < 2) {
      bars.add(_zoneBar(spots, zoneColors.first, showDots));
    } else {
      // Colour each segment (between two points) by its more-extreme endpoint,
      // so a dip below / spike above target is fully red / amber on both flanks.
      final segColors = [
        for (var i = 0; i < spots.length - 1; i++)
          _segColor(zoneColors[i], zoneColors[i + 1], gc),
      ];
      var runStart = 0;
      for (var i = 0; i < segColors.length; i++) {
        if (i == segColors.length - 1 || segColors[i + 1] != segColors[i]) {
          bars.add(
            _zoneBar(spots.sublist(runStart, i + 2), segColors[i], showDots),
          );
          runStart = i + 1;
        }
      }
    }
    // Transparent overlay over only the REAL readings: it owns touch, so the
    // tooltip + indicator snap to a single actual value instead of every zone
    // bar (which share boundary points) and the interpolated crossings.
    _touchBarIndex = bars.length;
    final touchBar = LineChartBarData(
      spots: realSpots,
      isCurved: true,
      curveSmoothness: 0.2,
      preventCurveOverShooting: true,
      barWidth: 0,
      color: Colors.transparent,
      dotData: const FlDotData(show: false),
    );
    bars.add(touchBar);

    final maxY = s.toDisplay(300);
    // Whole-unit gridlines that read cleanly in either unit.
    final yInterval = s.unit == GlucoseUnit.mmol ? 3.0 : 50.0;
    // Fewer X ticks for shorter windows so labels don't crowd.
    final xInterval = rangeHours <= 6
        ? 2.0
        : rangeHours <= 12
        ? 3.0
        : 6.0;

    final chart = LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        minX: minX,
        maxX: shift,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: yInterval,
              getTitlesWidget: (v, _) => Text(
                s.unit == GlucoseUnit.mmol
                    ? v.toStringAsFixed(0)
                    : '${v.toInt()}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: xInterval,
              // Drop the fractional min/max edge ticks so only full hours show.
              minIncluded: false,
              maxIncluded: false,
              getTitlesWidget: (v, _) {
                if (anchor == null) {
                  return Text(
                    '${v.toInt()}h',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  );
                }
                // v is in shifted hours; (v - shift) hours back from the anchor
                // lands on a full clock hour.
                final t = anchor.add(
                  Duration(seconds: ((v - shift) * 3600).round()),
                );
                return Text(
                  Locales.string(
                    context,
                    'overview.chart.hour',
                    params: ['${t.hour}'],
                  ),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                );
              },
            ),
          ),
        ),
        // User-configurable target range band.
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: s.toDisplay(s.targetLow),
              color: gc.low.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
            HorizontalLine(
              y: s.toDisplay(s.targetHigh),
              color: gc.high.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ],
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          touchCallback: _onChartTouch,
          // Only the transparent overlay bar shows a value/indicator → exactly
          // one reading at a time while scrubbing.
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItems: (touchedSpots) => [
              for (final sp in touchedSpots)
                if (sp.barIndex == _touchBarIndex)
                  LineTooltipItem(
                    '${sp.y.toStringAsFixed(s.unit == GlucoseUnit.mmol ? 1 : 0)} ${s.unit.label}',
                    TextStyle(
                      color: theme.colorScheme.onInverseSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  )
                else
                  null,
            ],
          ),
          getTouchedSpotIndicator: (barData, indexes) {
            // fl_chart passes a copyWith of the bar (with showingIndicators
            // set), so compare by a stable property, not reference: the touch
            // overlay is the only zero-width bar; colour bars get no indicator.
            if (barData.barWidth != 0) {
              return List<TouchedSpotIndicatorData?>.filled(
                indexes.length,
                null,
              );
            }
            return [
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
                      color: _zoneForDisplay(spot.y, s, gc),
                      strokeColor: Colors.white,
                      strokeWidth: 1.5,
                    ),
                  ),
                ),
            ];
          },
        ),
        lineBarsData: bars,
      ),
      // No implicit morph animation: the number of zone bars changes between
      // states, so fl_chart would interpolate between mismatched structures —
      // which looked broken on load/update. Render each state directly.
      duration: Duration.zero,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(alignment: Alignment.centerLeft, child: _rangeSelector(context)),
        const SizedBox(height: 20),
        Expanded(child: chart),
      ],
    );
  }

  /// Segmented control to pick the visible time window.
  Widget _rangeSelector(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final h in const [24, 12, 6]) _rangeChip(theme, h),
        ],
      ),
    );
  }

  Widget _rangeChip(ThemeData theme, int hours) {
    final selected = _rangeHours == hours;
    return GestureDetector(
      onTap: () => _setRange(hours),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${hours}h',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  /// Zone colour for a display-unit Y value (used for the touch dot).
  Color _zoneForDisplay(double y, ProfileGlucoseState s, GlucoseColors gc) {
    if (y < s.toDisplay(s.targetLow)) {
      return gc.low;
    }
    if (y > s.toDisplay(s.targetHigh)) {
      return gc.high;
    }
    return gc.inRange;
  }

  /// Colour for the segment between two points: red if either end is below
  /// target, amber if either is above, else in-range green.
  Color _segColor(Color a, Color b, GlucoseColors gc) {
    if (a == gc.low || b == gc.low) {
      return gc.low;
    }
    if (a == gc.high || b == gc.high) {
      return gc.high;
    }
    return gc.inRange;
  }

  /// A solid, single-colour line piece (+ faded fill below it) for one zone run.
  LineChartBarData _zoneBar(List<FlSpot> spots, Color color, bool showDots) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.2,
      barWidth: 3,
      color: color,
      dotData: FlDotData(show: showDots),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.15),
      ),
    );
  }
}
