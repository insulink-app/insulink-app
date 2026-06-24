import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/statistics/ranges/glucose_band.dart';
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

List<GlucoseBand> bandsFor(Iterable<int> values) => TimeInRangeBands(
  values: values,
  glucose: glucoseState(),
  colors: GlucoseColors.standard,
).build();

/// Reads a band's percent label by its slug suffix.
String pct(List<GlucoseBand> bands, String slug) => bands
    .firstWhere((band) => band.labelKey == 'statistics.range.$slug')
    .pctLabel;

void main() {
  group('TimeInRangeBands', () {
    test('returns no bands for empty input', () {
      expect(bandsFor(const []), isEmpty);
    });

    test('counts readings into the five zones, top→bottom', () {
      // very_high 1, high 1, in_range 5, low 2, very_low 1 (total 10).
      final values = [300, 200, 100, 100, 100, 100, 100, 60, 60, 40];
      final bands = bandsFor(values);
      expect(bands.map((band) => band.labelKey).toList(), [
        'statistics.range.very_high',
        'statistics.range.high',
        'statistics.range.in_range',
        'statistics.range.low',
        'statistics.range.very_low',
      ]);
      expect(pct(bands, 'very_high'), '10%');
      expect(pct(bands, 'high'), '10%');
      expect(pct(bands, 'in_range'), '50%');
      expect(pct(bands, 'low'), '20%');
      expect(pct(bands, 'very_low'), '10%');
    });

    test('zone boundaries are inclusive on the in-range side', () {
      // urgentLow=55, targetLow=70, targetHigh=180, urgentHigh=250.
      expect(
        bandsFor([70]).firstWhere((b) => b.fraction > 0).labelKey,
        'statistics.range.in_range',
      );
      expect(
        bandsFor([180]).firstWhere((b) => b.fraction > 0).labelKey,
        'statistics.range.in_range',
      );
      expect(
        bandsFor([250]).firstWhere((b) => b.fraction > 0).labelKey,
        'statistics.range.high',
      );
      expect(
        bandsFor([54]).firstWhere((b) => b.fraction > 0).labelKey,
        'statistics.range.very_low',
      );
    });

    test('integer percents always sum to exactly 100', () {
      final values = List<int>.generate(7, (index) => 50 + index * 40);
      final bands = bandsFor(values);
      final total = bands
          .map(
            (band) =>
                int.parse(band.pctLabel.replaceAll(RegExp(r'[^0-9]'), '')),
          )
          .where((percent) => percent > 0)
          .fold<int>(0, (sum, percent) => sum + percent);
      expect(total, 100);
    });

    test('a non-empty band that rounds to 0% shows "<1%"', () {
      // 999 in-range + 1 very-high: very-high is ~0.1%, floored away.
      final values = [...List<int>.filled(999, 100), 300];
      expect(pct(bandsFor(values), 'very_high'), '<1%');
    });

    test('a truly empty band shows "0%"', () {
      expect(pct(bandsFor(List<int>.filled(10, 100)), 'very_high'), '0%');
    });
  });
}
