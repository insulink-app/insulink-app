import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/overview/chart/glucose_slope_series.dart';

import 'glucose_chart_series_test.dart' show glucoseState;

/// A reading every 5 min, x in hours as the chart plots them.
FlSpot reading(int minute, double mgdl) => FlSpot(minute / 60, mgdl);

void main() {
  test('slope in mg/dL per minute for every reading, broken at a gap', () {
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
    expect(slope.spots.first.y, closeTo(2, 1e-9));
    expect(slope.spots[1].y, closeTo(2, 1e-9));
    expect(slope.spots[2].x, closeTo(10 / 60, 1e-9));
    expect(slope.spots[2].y, closeTo(2, 1e-9));
    expect(slope.spots[3].isNull(), isTrue);
    expect(slope.spots[4].x, closeTo(1, 1e-9));
    expect(slope.spots[4].y, closeTo(-4, 1e-9));
    expect(slope.spots.last.x, closeTo(70 / 60, 1e-9));
    expect(slope.spots.last.y, closeTo(-4, 1e-9));
    expect(slope.touchSpots.length, 6);
    expect(slope.formatReading(2), '+2.0 mg/dL/min');
  });
}
