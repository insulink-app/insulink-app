import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/statistics/averages/glucose_summary.dart';

ProfileGlucoseState glucoseState({GlucoseUnit unit = GlucoseUnit.mgdl}) {
  return ProfileGlucoseState(
    unit: unit,
    targetLow: 70,
    targetHigh: 180,
    urgentLow: 55,
    low: 70,
    high: 180,
    urgentHigh: 250,
  );
}

/// Reads a stat tile's value by its locale key suffix (`mean`, `gmi`, …).
String statValue(List<GlucoseStat> stats, String suffix) =>
    stats.firstWhere((stat) => stat.labelKey == 'statistics.avg.$suffix').value;

void main() {
  group('GlucoseSummary', () {
    test('computes mean, extremes and zero spread for a flat series', () {
      final stats = GlucoseSummary([100, 100, 100], glucoseState()).build();
      expect(statValue(stats, 'mean'), '100');
      expect(statValue(stats, 'sd'), '0');
      expect(statValue(stats, 'cv'), '0.0');
      expect(statValue(stats, 'max'), '100');
      expect(statValue(stats, 'min'), '100');
    });

    test('computes standard deviation and CV for a spread series', () {
      // [80, 120] → mean 100, population sd 20, cv 20%.
      final stats = GlucoseSummary([80, 120], glucoseState()).build();
      expect(statValue(stats, 'mean'), '100');
      expect(statValue(stats, 'sd'), '20');
      expect(statValue(stats, 'cv'), '20.0');
      expect(statValue(stats, 'max'), '120');
      expect(statValue(stats, 'min'), '80');
    });

    test('GMI uses the standard CGM formula 3.31 + 0.02392 * mean', () {
      final stats = GlucoseSummary([100], glucoseState()).build();
      expect(statValue(stats, 'gmi'), '5.7'); // 3.31 + 2.392 = 5.702
    });

    test('formats values in the chosen display unit', () {
      final stats = GlucoseSummary([
        90,
      ], glucoseState(unit: GlucoseUnit.mmol)).build();
      // 90 mg/dL ≈ 5.0 mmol/L; unit label switches too.
      expect(statValue(stats, 'mean'), '5.0');
      expect(stats.first.unit, 'mmol/L');
    });

    test('produces exactly the six expected stat tiles', () {
      final stats = GlucoseSummary([100], glucoseState()).build();
      expect(
        stats.map((stat) => stat.labelKey),
        containsAll(<String>[
          'statistics.avg.mean',
          'statistics.avg.gmi',
          'statistics.avg.cv',
          'statistics.avg.sd',
          'statistics.avg.max',
          'statistics.avg.min',
        ]),
      );
      expect(stats, hasLength(6));
    });
  });
}
