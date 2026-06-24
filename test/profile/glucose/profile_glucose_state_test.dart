import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';

ProfileGlucoseState state(GlucoseUnit unit) => ProfileGlucoseState(
  unit: unit,
  targetLow: 70,
  targetHigh: 180,
  urgentLow: 55,
  low: 70,
  high: 180,
  urgentHigh: 250,
);

void main() {
  group('GlucoseUnit.label', () {
    test('renders the unit suffix', () {
      expect(GlucoseUnit.mgdl.label, 'mg/dL');
      expect(GlucoseUnit.mmol.label, 'mmol/L');
    });
  });

  group('ProfileGlucoseState display', () {
    test('mg/dL passes values through unchanged', () {
      final glucose = state(GlucoseUnit.mgdl);
      expect(glucose.toDisplay(120), 120.0);
      expect(glucose.format(120), '120');
      expect(glucose.formatWithUnit(120), '120 mg/dL');
    });

    test('mmol/L converts with the molar factor and one decimal', () {
      final glucose = state(GlucoseUnit.mmol);
      expect(glucose.toDisplay(180), closeTo(9.99, 0.01));
      expect(glucose.format(180), '10.0');
      expect(glucose.formatWithUnit(180), '10.0 mmol/L');
    });

    test('formatTrend is signed, one decimal in mg/dL', () {
      final glucose = state(GlucoseUnit.mgdl);
      expect(glucose.formatTrend(1.0), '+1.0');
      expect(glucose.formatTrend(-0.5), '-0.5');
      expect(glucose.formatTrend(0), '+0.0');
    });

    test('formatTrend converts and uses two decimals in mmol/L', () {
      final glucose = state(GlucoseUnit.mmol);
      // 1.0 mg/dL/min ≈ 0.06 mmol/L/min.
      expect(glucose.formatTrend(1.0), '+0.06');
    });
  });
}
