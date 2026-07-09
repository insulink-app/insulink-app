import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'heart_rate_zones.dart';

/// Splits the pulse line into solid-colour segments by heart-rate zone (green /
/// orange / red), inserting a point exactly where the line crosses a zone
/// threshold so the colour flips at the boundary — not at the first out-of-zone
/// sample. Pure (no BuildContext), so it stays unit-testable. Modelled on the
/// glucose chart's zone splitter, but its own class: the glucose one is coupled
/// to that domain's low/in/high thresholds.
class HeartRateChartSeries {
  HeartRateChartSeries({required this.points, required this.zones});

  /// Samples as chart spots (x = hours, y = bpm), ascending in x.
  final List<FlSpot> points;
  final HeartRateZones zones;

  final List<FlSpot> _spots = [];
  final List<int> _zoneIdx = [];

  /// All plotted spots including the interpolated threshold crossings — also the
  /// touch overlay's spots, so scrubbing snaps to every sample.
  List<FlSpot> get spots => _spots;

  List<LineChartBarData> buildBars() {
    _collect();
    return _bars();
  }

  void _collect() {
    double? prevY;
    double? prevX;
    for (final point in points) {
      if (prevY != null) {
        _addCrossings(prevY, prevX!, point.y, point.x);
      }
      _spots.add(point);
      _zoneIdx.add(zones.zoneOf(point.y));
      prevY = point.y;
      prevX = point.x;
    }
  }

  /// Insert a point where the segment crosses a threshold, tagged to the LOWER
  /// adjacent zone (the threshold index) so the colour break lands exactly on it.
  void _addCrossings(double prevY, double prevX, double y, double x) {
    final thresholds = [zones.elevated, zones.high];
    final crossings = <({double x, int zone})>[];
    for (var index = 0; index < thresholds.length; index++) {
      final threshold = thresholds[index];
      if ((prevY < threshold) != (y < threshold)) {
        final frac = (threshold - prevY) / (y - prevY);
        if (frac > 0 && frac < 1) {
          crossings.add((x: prevX + frac * (x - prevX), zone: index));
        }
      }
    }
    crossings.sort((left, right) => left.x.compareTo(right.x));
    for (final crossing in crossings) {
      final threshold = crossing.zone == 0 ? zones.elevated : zones.high;
      _spots.add(FlSpot(crossing.x, threshold.toDouble()));
      _zoneIdx.add(crossing.zone);
    }
  }

  /// Group contiguous same-colour segments into one bar each (a segment's colour
  /// is the higher zone of its two endpoints, so any excursion is coloured).
  List<LineChartBarData> _bars() {
    if (_spots.length < 2) {
      return _spots.isEmpty ? [] : [_bar(_spots, zones.colors[_zoneIdx.first])];
    }
    final segColors = [
      for (var index = 0; index < _spots.length - 1; index++)
        zones.colors[
            _zoneIdx[index] > _zoneIdx[index + 1]
                ? _zoneIdx[index]
                : _zoneIdx[index + 1]],
    ];
    final bars = <LineChartBarData>[];
    var runStart = 0;
    for (var index = 0; index < segColors.length; index++) {
      if (index == segColors.length - 1 ||
          segColors[index + 1] != segColors[index]) {
        bars.add(_bar(_spots.sublist(runStart, index + 2), segColors[index]));
        runStart = index + 1;
      }
    }
    return bars;
  }

  LineChartBarData _bar(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.15,
      preventCurveOverShooting: true,
      barWidth: 3,
      color: color,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.12),
      ),
    );
  }
}
