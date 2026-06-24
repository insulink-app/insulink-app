import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';

import '../../support/secure_storage_mock.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('setters keep thumbs ordered and clamped, and persist', () {
    late Map<String, String> backing;
    setUp(() {
      backing = installSecureStorageMock();
    });

    test('setUnit only writes on a real change', () async {
      final glucose = state(GlucoseUnit.mgdl);
      await glucose.setUnit(GlucoseUnit.mgdl);
      expect(backing.containsKey('glucose_unit'), isFalse);
      await glucose.setUnit(GlucoseUnit.mmol);
      expect(glucose.unit, GlucoseUnit.mmol);
      expect(backing['glucose_unit'], 'mmol');
    });

    test('target range clamps low into bounds and high above low', () async {
      final glucose = state(GlucoseUnit.mgdl);
      await glucose.setTargetRange(10, 5);
      expect(glucose.targetLow, ProfileGlucoseState.minMgdl);
      expect(glucose.targetHigh, ProfileGlucoseState.minMgdl);
      expect(backing['glucose_target_low'], '${ProfileGlucoseState.minMgdl}');
      expect(backing['glucose_target_high'], '${ProfileGlucoseState.minMgdl}');
    });

    test('low alarms keep urgent-low ≤ low', () async {
      final glucose = state(GlucoseUnit.mgdl);
      await glucose.setLowAlarms(80, 60);
      expect(glucose.urgentLow, 80);
      expect(glucose.low, 80);
    });

    test('high alarms keep high ≤ urgent-high and clamp to max', () async {
      final glucose = state(GlucoseUnit.mgdl);
      await glucose.setHighAlarms(999, 100);
      expect(glucose.high, ProfileGlucoseState.maxMgdl);
      expect(glucose.urgentHigh, ProfileGlucoseState.maxMgdl);
    });
  });

  group('persistence', () {
    setUp(installSecureStorageMock);

    test('load applies defaults when nothing is stored', () async {
      final glucose = await ProfileGlucoseState.load();
      expect(glucose.unit, GlucoseUnit.mgdl);
      expect(glucose.targetLow, ProfileGlucoseState.defTargetLow);
      expect(glucose.urgentHigh, ProfileGlucoseState.defUrgentHigh);
    });

    test('load reads back what setters persisted', () async {
      final written = state(GlucoseUnit.mgdl);
      await written.setUnit(GlucoseUnit.mmol);
      await written.setLowAlarms(50, 65);
      final reloaded = await ProfileGlucoseState.load();
      expect(reloaded.unit, GlucoseUnit.mmol);
      expect(reloaded.urgentLow, 50);
      expect(reloaded.low, 65);
    });

    test('loadThresholds returns just unit + the four alarm levels', () async {
      final written = state(GlucoseUnit.mgdl);
      await written.setHighAlarms(190, 260);
      final thresholds = await ProfileGlucoseState.loadThresholds();
      expect(thresholds.unit, GlucoseUnit.mgdl);
      expect(thresholds.high, 190);
      expect(thresholds.urgentHigh, 260);
    });
  });
}
