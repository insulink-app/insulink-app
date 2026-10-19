import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';

/// The rate of change of the plotted readings, in the display unit per minute,
/// shown by the detail chart IN PLACE OF the glucose line. Also carries the
/// y scale and labels that view needs, since the glucose ones mean nothing for
/// a slope.
///
/// Each point is the central difference between its two neighbours, which
/// halves the sensor noise a plain neighbour-to-neighbour difference shows. A
/// data gap breaks the line, as it breaks the glucose line.
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

  void _collect(List<FlSpot> realSpots) {
    for (var index = 1; index < realSpots.length - 1; index++) {
      final before = realSpots[index - 1];
      final after = realSpots[index + 1];
      final span = after.x - before.x;
      if (span <= 0 || span > 2 * _maxGapHours) {
        if (spots.isNotEmpty && !spots.last.isNull()) {
          spots.add(FlSpot.nullSpot);
        }
        continue;
      }
      final perMinute = (after.y - before.y) / (span * 60);
      spots.add(FlSpot(realSpots[index].x, perMinute.clamp(minY, maxY)));
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
