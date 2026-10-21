import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';

/// The rate of change of the plotted readings, in the display unit per minute,
/// shown by the detail chart IN PLACE OF the glucose line. Also carries the
/// y scale and labels that view needs, since the glucose ones mean nothing for
/// a slope.
///
/// Each point is the central difference between its two neighbours, which
/// halves the sensor noise a plain neighbour-to-neighbour difference shows. At
/// the ends of the data and of each gap it falls back to the one neighbour
/// there is. A data gap breaks the line, as it breaks the glucose line.
class GlucoseSlopeSeries {
  GlucoseSlopeSeries({
    required List<FlSpot> realSpots,
    required this.glucose,
    required this.color,
  }) {
    _collect(realSpots);
  }

  final ProfileGlucoseState glucose;
  final Color color;

  /// The plotted line, with [FlSpot.nullSpot] at each gap.
  final List<FlSpot> spots = [];

  /// The same points without the gap markers, for the touch overlay.
  List<FlSpot> get touchSpots => [
    for (final spot in spots)
      if (!spot.isNull()) spot,
  ];

  /// The slope at the plot's top and bottom edge. A fast rise or fall is around
  /// 3 mg/dL per minute, so this leaves headroom without flattening the curve;
  /// anything steeper is drawn on the edge.
  static const fullScaleMgdlPerMin = 4;

  /// Neighbours further apart than this (in hours) are a gap, not a slope.
  static const _maxGapHours = 20 / 60;

  double get maxY => glucose.toDisplay(fullScaleMgdlPerMin);
  double get minY => -maxY;

  /// Zero plus one line either side of it.
  List<double> get axisLabels => [
    -glucose.toDisplay(2),
    0,
    glucose.toDisplay(2),
  ];

  int get _digits => glucose.unit == GlucoseUnit.mmol ? 2 : 0;

  String formatAxis(double value) => _signed(value, _digits);

  /// The scrub readout: one digit more than the axis, with the unit.
  String formatReading(double value) =>
      '${_signed(value, _digits + 1)} ${glucose.unit.label}/min';

  String _signed(double value, int digits) {
    final text = value.toStringAsFixed(digits);
    return value > 0 ? '+$text' : text;
  }

  /// Each reading takes the difference between its neighbours that lie within
  /// [_maxGapHours]: central with both, one-sided with one. So the newest
  /// reading and the last one before a gap get a slope too. A reading with no
  /// near neighbour has none, and a gap breaks the line.
  void _collect(List<FlSpot> realSpots) {
    for (var index = 0; index < realSpots.length; index++) {
      final before = _neighbour(realSpots, index, index - 1);
      final after = _neighbour(realSpots, index, index + 1);
      if (before == realSpots[index]) {
        _breakLine();
      }
      if (after.x > before.x) {
        final perMinute = (after.y - before.y) / ((after.x - before.x) * 60);
        spots.add(FlSpot(realSpots[index].x, perMinute.clamp(minY, maxY)));
      }
    }
  }

  /// The reading at [neighbourIndex] when it exists and is near the one at
  /// [index], else the reading at [index] itself.
  FlSpot _neighbour(List<FlSpot> realSpots, int index, int neighbourIndex) {
    if (neighbourIndex < 0 || neighbourIndex >= realSpots.length) {
      return realSpots[index];
    }
    final neighbour = realSpots[neighbourIndex];
    final distance = (neighbour.x - realSpots[index].x).abs();
    return distance > 0 && distance <= _maxGapHours
        ? neighbour
        : realSpots[index];
  }

  void _breakLine() {
    if (spots.isNotEmpty && !spots.last.isNull()) {
      spots.add(FlSpot.nullSpot);
    }
  }

  /// Its non-zero barWidth keeps the scrub indicator off it, like the meal bar.
  LineChartBarData bar() {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.2,
      preventCurveOverShooting: true,
      barWidth: 2,
      color: color,
      dotData: const FlDotData(show: false),
    );
  }
}
