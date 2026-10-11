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
        const MapEntry(600, 100),
      ]);
      series.buildBars();

      expect(series.realSpots, hasLength(2));
      expect(series.spots, hasLength(3)); // two readings + one crossing
      final crossing = series.spots[1];
      expect(crossing.x, closeTo(-0.125, 1e-9)); // -1/6 + 0.25 * 1/6
      expect(crossing.y, 70); // sits on the target line
    });

    test('inserts both crossings when a segment spans low and high', () {
      // 60 → 200 crosses targetLow (70) then targetHigh (180), sorted by x.
      final series = seriesFor([
        const MapEntry(0, 60),
        const MapEntry(600, 200),
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
        const MapEntry(600, 120),
      ]);
      series.buildBars();
      expect(series.spots, hasLength(2));
      expect(series.spots, equals(series.realSpots));
    });

    test('keeps only the last reading just before the cutoff, drops the rest', () {
      // The reading right below the cutoff must survive so its segment can enter
      // the viewport from the left; readings before THAT are truly off-window.
      final series = GlucoseChartSeries(
        entries: const [
          MapEntry(0, 90),
          MapEntry(500, 100),
          MapEntry(3600, 110),
        ],
        latestSecs: 3600,
        cutoff: 1000,
        shift: 0,
        glucose: glucoseState(),
        colors: GlucoseColors.standard,
      );
      series.buildBars();
      expect(series.realSpots, hasLength(2));
      expect(series.realSpots.map((spot) => spot.y), [100, 110]);
    });

    test('a data gap breaks the line instead of bridging it', () {
      // Two stretches seven hours apart: each draws its own bar, and nothing
      // connects the last reading before the gap to the first one after it.
      final series = seriesFor([
        const MapEntry(0, 150),
        const MapEntry(300, 155),
        const MapEntry(25200, 160),
        const MapEntry(25500, 165),
      ]);
      final bars = series.buildBars();
      expect(bars, hasLength(2));
      expect(bars.map((bar) => bar.spots.length), [2, 2]);
      expect(series.realSpots, hasLength(4));
    });

    test('readings within the gap limit stay one line', () {
      final series = seriesFor([
        const MapEntry(0, 150),
        const MapEntry(900, 155),
        const MapEntry(1800, 160),
      ]);
      expect(series.buildBars(), hasLength(1));
    });

    test('a window under the cap is plotted untouched', () {
      // 288 points = the G7's 24 h; below the 400-point cap, so every reading is
      // kept (plus the target crossings the zone split adds).
      final series = seriesFor([
        for (var index = 0; index < 288; index++) MapEntry(index * 300, 100),
      ]);
      series.buildBars();
      expect(series.realSpots, hasLength(288));
    });

    test('a dense window is thinned but keeps its extremes and endpoints', () {
      // 1440 points = the Libre's 24 h at 1-min cadence, with a single spike and
      // a single dip buried in an otherwise flat line. Both must survive the thin.
      final entries = [
        for (var index = 0; index < 1440; index++)
          MapEntry(index * 60, index == 700 ? 260 : (index == 900 ? 45 : 100)),
      ];
      final series = seriesFor(entries);
      series.buildBars();

      expect(series.realSpots.length, lessThan(1440));
      expect(series.realSpots.length, lessThanOrEqualTo(402));
      final values = series.realSpots.map((spot) => spot.y).toList();
      expect(values, contains(260)); // the spike
      expect(values, contains(45)); // the dip
      expect(values.first, 100); // first reading kept
      expect(values.last, 100); // last (current) reading kept
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
