import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/overview/chart/glucose_chart_series.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';

ProfileGlucoseState glucoseState() => ProfileGlucoseState(
  unit: GlucoseUnit.mgdl,
  targetLow: 70,
  targetHigh: 180,
  urgentLow: 55,
  low: 70,
  high: 180,
  urgentHigh: 250,
);

GlucoseChartSeries seriesFor(List<MapEntry<int, int>> entries) {
  return GlucoseChartSeries(
    entries: entries,
    latestSecs: entries.last.key,
    cutoff: -1 << 30,
    shift: 0,
    glucose: glucoseState(),
    colors: GlucoseColors.standard,
  );
}

void main() {
  group('GlucoseChartSeries crossings', () {
    test('inserts a point exactly where a segment crosses a target line', () {
      // 60 → 100 crosses targetLow (70) at frac 0.25 of the segment.
      final series = seriesFor([
        const MapEntry(0, 60),
        const MapEntry(3600, 100),
      ]);
      series.buildBars();

      expect(series.realSpots, hasLength(2));
      expect(series.spots, hasLength(3)); // two readings + one crossing
      final crossing = series.spots[1];
      expect(crossing.x, closeTo(-0.75, 1e-9)); // -1.0 + 0.25
      expect(crossing.y, 70); // sits on the target line
    });

    test('inserts both crossings when a segment spans low and high', () {
      // 60 → 200 crosses targetLow (70) then targetHigh (180), sorted by x.
      final series = seriesFor([
        const MapEntry(0, 60),
        const MapEntry(3600, 200),
      ]);
      series.buildBars();

      expect(series.spots, hasLength(4));
      expect(series.spots[1].y, 70);
      expect(series.spots[2].y, 180);
      expect(series.spots[1].x, lessThan(series.spots[2].x));
    });

    test('no crossing when both readings sit in the same zone', () {
      final series = seriesFor([
        const MapEntry(0, 100),
        const MapEntry(3600, 120),
      ]);
      series.buildBars();
      expect(series.spots, hasLength(2));
      expect(series.spots, equals(series.realSpots));
    });

    test('readings older than the cutoff are dropped', () {
      final series = GlucoseChartSeries(
        entries: const [MapEntry(0, 100), MapEntry(3600, 110)],
        latestSecs: 3600,
        cutoff: 1000, // drops the key-0 reading
        shift: 0,
        glucose: glucoseState(),
        colors: GlucoseColors.standard,
      );
      series.buildBars();
      expect(series.realSpots, hasLength(1));
      expect(series.realSpots.single.y, 110);
    });

    test('shows dots only for sparse series (< 60 points)', () {
      final sparse = seriesFor([
        const MapEntry(0, 100),
        const MapEntry(3600, 110),
      ]);
      sparse.buildBars();
      expect(sparse.showDots, isTrue);

      final dense = seriesFor([
        for (var index = 0; index < 80; index++) MapEntry(index * 300, 100),
      ]);
      dense.buildBars();
      expect(dense.showDots, isFalse);
    });
  });
}
