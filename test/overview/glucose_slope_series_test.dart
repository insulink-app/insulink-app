import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/overview/chart/glucose_slope_series.dart';

import 'glucose_chart_series_test.dart' show glucoseState;

/// A reading every 5 min, x in hours as the chart plots them.
FlSpot reading(int minute, double mgdl) => FlSpot(minute / 60, mgdl);

void main() {
  test('central difference in mg/dL per minute, broken at a gap', () {
    final slope = GlucoseSlopeSeries(
      realSpots: [
        reading(0, 100),
        reading(5, 110),
        reading(10, 120),
        reading(60, 120),
        reading(65, 100),
        reading(70, 80),
      ],
      glucose: glucoseState(),
      color: Colors.blue,
    );
    expect(slope.spots[0].y, closeTo(2, 1e-9));
    expect(slope.spots[1].isNull(), isTrue);
    expect(slope.spots.last.y, closeTo(-4, 1e-9));
    expect(slope.touchSpots.length, 2);
    expect(slope.formatReading(2), '+2.0 mg/dL/min');
  });
}
