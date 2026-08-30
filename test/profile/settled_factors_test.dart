import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/tuning/factor_suggestion.dart';
import 'package:insulink/src/profile/tuning/settled_factors.dart';
import 'package:insulink/src/profile/tuning/tuning_dose.dart';

/// The reported symptom: adopt all three, press again, get another round of
/// changes, twice over. The three settings move each other, so one round of the
/// arithmetic is not the answer, only a step towards it.
void main() {
  final monday = DateTime(2026, 5, 4);

  TuningDose mealWindow({
    required double carbs,
    required double insulin,
    int drift = 0,
    int? minutesToLowest,
  }) =>
      TuningDose(
        at: monday,
        carbsAbsorbed: carbs,
        insulinActing: insulin,
        startMgdl: 140,
        endMgdl: 140 + drift,
        minutesToEnd: 300,
        minutesToLowest: minutesToLowest,
        isCorrection: false,
      );

  TuningDose correction({required double insulin, required int drop}) =>
      TuningDose(
        at: monday,
        carbsAbsorbed: 0,
        insulinActing: insulin,
        startMgdl: 220,
        endMgdl: 220 - drop,
        minutesToEnd: 300,
        minutesToLowest: 300,
        isCorrection: true,
      );

  /// Windows that pull all three settings at once: the corrections say 50 mg/dL
  /// per unit against a setting of 30, the meals drifted up so their ratio
  /// depends on that correction factor, and the falls take five hours against a
  /// duration of 3.
  List<TuningDose> windows(int insulinDurationH) => [
        for (var dose = 0; dose < 8; dose++) correction(insulin: 2, drop: 100),
        for (var meal = 0; meal < 8; meal++)
          mealWindow(carbs: 60, insulin: 4, drift: 40, minutesToLowest: 300),
      ];

  SettledFactors settling({
    required int correctionFactor,
    required int carbFactor,
    required int insulinDurationH,
  }) =>
      SettledFactors(
        windowsFor: windows,
        correctionFactor: correctionFactor,
        carbFactor: carbFactor,
        insulinDurationH: insulinDurationH,
      );

  test('the answer reproduces itself, so a second press changes nothing', () {
    final settled = settling(
      correctionFactor: 30,
      carbFactor: 15,
      insulinDurationH: 3,
    ).solve();

    final again = settling(
      correctionFactor: settled['correction']?.suggested ?? 30,
      carbFactor: settled['carb']?.suggested ?? 15,
      insulinDurationH: settled['duration']?.suggested ?? 3,
    ).solve();

    expect(again.values.every((suggestion) => !suggestion.isChange), isTrue,
        reason: 'pressing again after adopting must find nothing to do');
  });

  /// One round of the arithmetic is NOT the answer: the carbohydrate factor is
  /// measured against the correction factor, so it lands somewhere else once the
  /// correction factor has moved.
  test('it settles somewhere a single round does not reach', () {
    final oneRound = const FactorSuggestions(
      correctionFactor: 30,
      carbFactor: 15,
      insulinDurationH: 3,
    ).carb(windows(3));

    final settled = settling(
      correctionFactor: 30,
      carbFactor: 15,
      insulinDurationH: 3,
    ).solve();

    expect(settled['carb']!.suggested, isNot(oneRound!.suggested));
  });

  /// Every row is stated against what the USER runs, not against the working
  /// value the last round happened to use.
  test('the rows are stated against the settings in use', () {
    final settled = settling(
      correctionFactor: 30,
      carbFactor: 15,
      insulinDurationH: 3,
    ).solve();

    expect(settled['correction']!.current, 30);
    expect(settled['carb']!.current, 15);
    expect(settled['duration']!.current, 3);
  });

  /// A setting the windows cannot answer for stays absent through every round.
  test('an unanswerable setting is simply missing', () {
    final settled = SettledFactors(
      windowsFor: (_) => [
        for (var meal = 0; meal < 8; meal++)
          mealWindow(carbs: 60, insulin: 4),
      ],
      correctionFactor: 35,
      carbFactor: 15,
      insulinDurationH: 3,
    ).solve();

    expect(settled.containsKey('carb'), isTrue);
    expect(settled.containsKey('correction'), isFalse);
    expect(settled.containsKey('duration'), isFalse);
  });
}
