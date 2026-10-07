import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/google_health/heart_rate_chart_series.dart';
import 'package:insulink/src/google_health/heart_rate_zones.dart';

const _below = Color(0xFF0000FF);
const _above = Color(0xFFFF00FF);
const _palette = [_below, _above, _above];

void main() {
  group('HeartRateZones', () {
    test('classifies bpm into the three zones', () {
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
      // 90 (below) → 120 (elevated): one threshold crossing at 100.
      final series = HeartRateChartSeries(
        points: const [FlSpot(0, 90), FlSpot(1, 120)],
        zones: zones,
        palette: _palette,
      );
      final bars = series.buildBars();
      expect(bars.length, 2);
      expect(bars.first.color, _below);
      expect(bars.last.color, _above);
      // a crossing spot was inserted exactly at the 100 bpm threshold
      expect(series.spots.any((s) => s.y == 100), isTrue);
    });

    test('a single zone stays one bar', () {
      final series = HeartRateChartSeries(
        points: const [FlSpot(0, 70), FlSpot(1, 80), FlSpot(2, 75)],
        zones: const HeartRateZones(),
        palette: _palette,
      );
      expect(series.buildBars(), hasLength(1));
    });
  });
}
