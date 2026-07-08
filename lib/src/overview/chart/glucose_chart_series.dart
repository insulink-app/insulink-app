import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';

/// Turns the raw glucose-by-time readings into the coloured line segments the
/// overview chart draws. UI-agnostic beyond fl_chart's data types: it owns the
/// zone colouring, the exact target-line crossings, and the split into solid
/// single-colour bars — none of which depend on a [BuildContext].
class GlucoseChartSeries {
  GlucoseChartSeries({
    required this.entries,
    required this.latestSecs,
    required this.cutoff,
    required this.shift,
    required this.glucose,
    required this.colors,
    this.windowEnd = 1 << 62,
  });

  /// All cached readings (secsSinceStart → mg/dL), oldest first.
  final List<MapEntry<int, int>> entries;

  /// secsSinceStart of the newest reading — the x == shift anchor.
  final int latestSecs;

  /// Readings older than this (secsSinceStart) are outside the window.
  final int cutoff;

  /// Readings newer than this (secsSinceStart) are outside the window — only
  /// below [latestSecs] when the user has paged back to an earlier interval.
  final int windowEnd;

  /// Phase shift so full clock hours land on integer x values.
  final double shift;
  final ProfileGlucoseState glucose;
  final GlucoseColors colors;

  /// All plotted points, including the interpolated target-line crossings.
  final List<FlSpot> spots = [];

  /// Real readings only (no crossings) — drives touch/tooltip snapping.
  final List<FlSpot> realSpots = [];

  final List<Color> _zoneColors = [];

  /// Whether to draw point dots — only sparse windows stay readable with them.
  bool get showDots => spots.length < 60;

  /// Collects the spots, then returns the zone-coloured line bars (one per
  /// contiguous same-colour run). Call once.
  List<LineChartBarData> buildBars() {
    _collectSpots();
    return _zoneBars();
  }

  void _collectSpots() {
    int? prevValue;
    double? prevX;
    for (final entry in entries) {
      if (entry.key < cutoff || entry.key > windowEnd) {
        continue;
      }
      final x = (entry.key - latestSecs) / 3600.0 + shift;
      final value = entry.value;
      if (prevValue != null) {
        _addCrossings(prevValue, prevX!, value, x);
      }
      final spot = FlSpot(x, glucose.toDisplay(value));
      spots.add(spot);
      realSpots.add(spot);
      _zoneColors.add(_zoneOf(value));
      prevValue = value;
      prevX = x;
    }
  }

  /// Where two readings straddle a target line, insert a point EXACTLY at the
  /// crossing so the colour flips at the line — not at the first out-of-range
  /// reading (which turned the curve red too early). Each crossing sits on the
  /// in-range edge of the band.
  void _addCrossings(int prevValue, double prevX, int value, double x) {
    final crossings = <MapEntry<double, int>>[];
    for (final threshold in [glucose.targetLow, glucose.targetHigh]) {
      if ((prevValue < threshold) != (value < threshold)) {
        final frac = (threshold - prevValue) / (value - prevValue);
        if (frac > 0 && frac < 1) {
          crossings.add(MapEntry(prevX + frac * (x - prevX), threshold));
        }
      }
    }
    crossings.sort((left, right) => left.key.compareTo(right.key));
    for (final crossing in crossings) {
      spots.add(FlSpot(crossing.key, glucose.toDisplay(crossing.value)));
      _zoneColors.add(colors.inRange);
    }
  }

  Color _zoneOf(int value) {
    if (value < glucose.targetLow) {
      return colors.low;
    }
    if (value > glucose.targetHigh) {
      return colors.high;
    }
    return colors.inRange;
  }

  /// Split the line into solid-colour segments by zone instead of blending a
  /// gradient across it: on steep parts the blend showed green and red running
  /// side by side (looked like two parallel lines). Each contiguous run of
  /// same-zone segments becomes its own bar, meeting the next at a shared point.
  List<LineChartBarData> _zoneBars() {
    if (spots.length < 2) {
      return [_zoneBar(spots, _zoneColors.first)];
    }
    final segColors = [
      for (var index = 0; index < spots.length - 1; index++)
        _segColor(_zoneColors[index], _zoneColors[index + 1]),
    ];
    final bars = <LineChartBarData>[];
    var runStart = 0;
    for (var index = 0; index < segColors.length; index++) {
      if (index == segColors.length - 1 ||
          segColors[index + 1] != segColors[index]) {
        bars.add(
          _zoneBar(spots.sublist(runStart, index + 2), segColors[index]),
        );
        runStart = index + 1;
      }
    }
    return bars;
  }

  /// Colour for the segment between two points: red if either end is below
  /// target, amber if either is above, else in-range green.
  Color _segColor(Color left, Color right) {
    if (left == colors.low || right == colors.low) {
      return colors.low;
    }
    if (left == colors.high || right == colors.high) {
      return colors.high;
    }
    return colors.inRange;
  }

  /// A solid, single-colour line piece (+ faded fill below it) for one zone run.
  LineChartBarData _zoneBar(List<FlSpot> spots, Color color) {
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
