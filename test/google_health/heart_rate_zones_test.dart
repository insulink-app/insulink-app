import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/google_health/heart_rate_chart_series.dart';
import 'package:insulink/src/google_health/heart_rate_zones.dart';

void main() {
  group('HeartRateZones', () {
    test('classifies bpm into green / orange / red', () {
      const zones = HeartRateZones(elevated: 100, high: 140);
      expect(zones.zoneOf(80), 0);
      expect(zones.zoneOf(120), 1);
      expect(zones.zoneOf(160), 2);
      // boundary belongs to the upper zone
      expect(zones.zoneOf(100), 1);
    });

    test('copyWith keeps thresholds ordered and in range', () {
      // elevated cannot pass high
      final crossed = const HeartRateZones(high: 130).copyWith(elevated: 200);
      expect(crossed.elevated, lessThan(crossed.high));
      // clamped to sane bounds
      final low = const HeartRateZones().copyWith(elevated: 10);
      expect(low.elevated, HeartRateZones.minBpm);
    });
  });

  group('HeartRateChartSeries', () {
    test('splits the line into a colour break at each zone crossing', () {
      const zones = HeartRateZones(elevated: 100, high: 140);
      // 90 (green) → 120 (orange): one threshold crossing at 100.
      final series = HeartRateChartSeries(
        points: const [FlSpot(0, 90), FlSpot(1, 120)],
        zones: zones,
      );
      final bars = series.buildBars();
      expect(bars.length, 2);
      expect(bars.first.color, HeartRateZones.green);
      expect(bars.last.color, HeartRateZones.orange);
      // a crossing spot was inserted exactly at the 100 bpm threshold
      expect(series.spots.any((s) => s.y == 100), isTrue);
    });

    test('a single zone stays one bar', () {
      final series = HeartRateChartSeries(
        points: const [FlSpot(0, 70), FlSpot(1, 80), FlSpot(2, 75)],
        zones: const HeartRateZones(),
      );
      expect(series.buildBars(), hasLength(1));
    });
  });
}
