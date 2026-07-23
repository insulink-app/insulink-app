import 'dart:math' as math;

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

  /// The most points worth plotting: a phone chart is a few hundred pixels wide,
  /// so beyond this the extra vertices only cost build + paint time. The Libre 3
  /// packs ~1440 readings into a 24 h window; the G7's ~288 stay under the cap and
  /// are drawn untouched.
  static const _maxPoints = 400;

  void _collectSpots() {
    int? prevValue;
    double? prevX;
    for (final entry in _downsample(_windowSlice())) {
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

  /// The readings to plot: everything inside `[cutoff, windowEnd]` PLUS the one
  /// reading just outside each edge. Those neighbours are what let a segment that
  /// only CROSSES the viewport render — the last reading before a gap sitting
  /// off-screen to the left, or a window that falls entirely between two distant
  /// readings. fl_chart clips the off-window points at the axis bounds, so they
  /// draw the entering/spanning line without being visible as points. Without
  /// them such a window renders blank until fresh in-window data arrives.
  /// [entries] is oldest-first, so the last sub-cutoff entry and the first
  /// past-windowEnd entry are the immediate neighbours.
  List<MapEntry<int, int>> _windowSlice() {
    final slice = <MapEntry<int, int>>[];
    MapEntry<int, int>? beforeLeft;
    for (final entry in entries) {
      if (entry.key < cutoff) {
        beforeLeft = entry;
        continue;
      }
      slice.add(entry);
      if (entry.key > windowEnd) {
        break;
      }
    }
    if (beforeLeft != null) {
      slice.insert(0, beforeLeft);
    }
    return slice;
  }

  /// Thins a dense window down to at most [_maxPoints] while KEEPING the shape:
  /// each bucket contributes its lowest and highest reading (in time order), so
  /// every spike and dip survives — only the flat stretches between them lose
  /// redundant vertices. The first and last readings are always kept so the line
  /// still spans the exact window and ends on the current value. A window already
  /// under the cap is returned unchanged.
  List<MapEntry<int, int>> _downsample(List<MapEntry<int, int>> slice) {
    if (slice.length <= _maxPoints) {
      return slice;
    }
    final bucketCount = _maxPoints ~/ 2;
    final bucketSize = slice.length / bucketCount;
    final out = <MapEntry<int, int>>[];
    for (var bucket = 0; bucket < bucketCount; bucket++) {
      final start = (bucket * bucketSize).floor();
      final end = math.min(((bucket + 1) * bucketSize).floor(), slice.length);
      var lowest = start;
      var highest = start;
      for (var index = start + 1; index < end; index++) {
        if (slice[index].value < slice[lowest].value) {
          lowest = index;
        }
        if (slice[index].value > slice[highest].value) {
          highest = index;
        }
      }
      final first = math.min(lowest, highest);
      final second = math.max(lowest, highest);
      out.add(slice[first]);
      if (second != first) {
        out.add(slice[second]);
      }
    }
    if (out.first != slice.first) {
      out.insert(0, slice.first);
    }
    if (out.last != slice.last) {
      out.add(slice.last);
    }
    return out;
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
