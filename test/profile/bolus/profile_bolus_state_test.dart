import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';

import '../../support/secure_storage_mock.dart';

ProfileBolusState bolusState({
  int correction = 35,
  int carb = 15,
  int maxBolus = ProfileBolusState.defMaxBolus,
  int insulinDurationH = ProfileBolusState.defInsulinDuration,
}) => ProfileBolusState(
  correctionFactor: correction,
  carbFactor: carb,
  maxBolus: maxBolus,
  insulinDurationH: insulinDurationH,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('suggestedBolus', () {
    test('meal dose only when glucose is at target', () {
      final dose = bolusState().suggestedBolus(
        carbs: 30,
        glucoseMgdl: 110,
        targetMgdl: 110,
        iobUnits: 0,
      );
      expect(dose, closeTo(2.0, 1e-9)); // 30 g / 15 g·u⁻¹
    });

    test('correction dose only when there are no carbs', () {
      final dose = bolusState().suggestedBolus(
        carbs: 0,
        glucoseMgdl: 180,
        targetMgdl: 110,
        iobUnits: 0,
      );
      expect(dose, closeTo(2.0, 1e-9)); // (180-110)/35
    });

    test('sums meal and correction', () {
      final dose = bolusState().suggestedBolus(
        carbs: 30,
        glucoseMgdl: 180,
        targetMgdl: 110,
        iobUnits: 0,
      );
      expect(dose, closeTo(4.0, 1e-9));
    });

    test('a low glucose reduces the meal dose', () {
      // meal 2.0, correction (75-110)/35 = -1.0 → 1.0.
      final dose = bolusState().suggestedBolus(
        carbs: 30,
        glucoseMgdl: 75,
        targetMgdl: 110,
        iobUnits: 0,
      );
      expect(dose, closeTo(1.0, 1e-9));
    });

    test('never suggests a negative dose', () {
      final dose = bolusState().suggestedBolus(
        carbs: 0,
        glucoseMgdl: 70,
        targetMgdl: 110,
        iobUnits: 0,
      );
      expect(dose, 0);
    });

    test('respects custom factors', () {
      final dose = bolusState(
        correction: 50,
        carb: 10,
      ).suggestedBolus(
        carbs: 20,
        glucoseMgdl: 160,
        targetMgdl: 100,
        iobUnits: 0,
      );
      expect(dose, closeTo(3.2, 1e-9)); // 20/10 + (60)/50
    });
  });

  group('suggestedBolus subtracts active insulin', () {
    test('active insulin comes off the correction', () {
      // correction (180-110)/35 = 2.0, less 0.5 U on board.
      final dose = bolusState().suggestedBolus(
        carbs: 0,
        glucoseMgdl: 180,
        targetMgdl: 110,
        iobUnits: 0.5,
      );
      expect(dose, closeTo(1.5, 1e-9));
    });

    test('active insulin beyond the correction never goes negative', () {
      final dose = bolusState().suggestedBolus(
        carbs: 0,
        glucoseMgdl: 180,
        targetMgdl: 110,
        iobUnits: 9,
      );
      expect(dose, 0);
    });

    test('active insulin never eats into the meal dose', () {
      // meal 2.0 stands; the 2.0 correction is wiped out by 9 U on board.
      final dose = bolusState().suggestedBolus(
        carbs: 30,
        glucoseMgdl: 180,
        targetMgdl: 110,
        iobUnits: 9,
      );
      expect(dose, closeTo(2.0, 1e-9));
    });

    test('a below-target correction still reduces the meal dose', () {
      // Not stacking but a real "already low-ish" signal: meal 2.0, correction
      // (75-110)/35 = -1.0, and the 5 U on board must not make it MORE negative.
      final dose = bolusState().suggestedBolus(
        carbs: 30,
        glucoseMgdl: 75,
        targetMgdl: 110,
        iobUnits: 5,
      );
      expect(dose, closeTo(1.0, 1e-9));
    });
  });

  group('suggestedRescueCarbs', () {
    test('grams to raise glucose up to target', () {
      // rise 60 mg/dL × 15 g·u⁻¹ / 35 mg/dL·u⁻¹ ≈ 25.7 g.
      final grams = bolusState().suggestedRescueCarbs(
        glucoseMgdl: 65,
        targetMgdl: 125,
      );
      expect(grams, closeTo(60 * 15 / 35, 1e-9));
    });

    test('no carbs when already at/above target', () {
      expect(
        bolusState().suggestedRescueCarbs(glucoseMgdl: 125, targetMgdl: 125),
        0,
      );
      expect(
        bolusState().suggestedRescueCarbs(glucoseMgdl: 140, targetMgdl: 125),
        0,
      );
    });

    test('respects custom factors', () {
      // rise 40 × 10 / 50 = 8 g.
      final grams = bolusState(
        correction: 50,
        carb: 10,
      ).suggestedRescueCarbs(glucoseMgdl: 60, targetMgdl: 100);
      expect(grams, closeTo(8.0, 1e-9));
    });
  });

  group('factor setters clamp to the allowed range', () {
    setUp(installSecureStorageMock);

    test('correction factor clamps to [min, max]', () async {
      final state = bolusState();
      await state.setCorrectionFactor(5);
      expect(state.correctionFactor, ProfileBolusState.minCorrection);
      await state.setCorrectionFactor(999);
      expect(state.correctionFactor, ProfileBolusState.maxCorrection);
    });

    test('carb factor clamps to [min, max]', () async {
      final state = bolusState();
      await state.setCarbFactor(1);
      expect(state.carbFactor, ProfileBolusState.minCarb);
      await state.setCarbFactor(999);
      expect(state.carbFactor, ProfileBolusState.maxCarb);
    });

    test('max bolus clamps to [min, max]', () async {
      final state = bolusState();
      await state.setMaxBolus(0);
      expect(state.maxBolus, ProfileBolusState.minMaxBolus);
      await state.setMaxBolus(999);
      expect(state.maxBolus, ProfileBolusState.maxMaxBolus);
    });

    test('insulin duration clamps to [min, max]', () async {
      final state = bolusState();
      await state.setInsulinDurationH(0);
      expect(state.insulinDurationH, ProfileBolusState.minInsulinDuration);
      await state.setInsulinDurationH(99);
      expect(state.insulinDurationH, ProfileBolusState.maxInsulinDuration);
    });

    test('insulin duration is exposed as a Duration', () {
      expect(
        bolusState(insulinDurationH: 4).insulinDuration,
        const Duration(hours: 4),
      );
    });
  });
}
