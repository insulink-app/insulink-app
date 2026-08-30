import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/tuning/factor_regression.dart';
import 'package:insulink/src/profile/tuning/factor_suggestion.dart';
import 'package:insulink/src/profile/tuning/tuning_dose.dart';

/// Getting the correction factor out of meals alone, for the user who never
/// boluses without eating. It only works while the insulin is not a pure
/// function of the carbohydrates, and the point of these tests is that the fit
/// KNOWS the difference instead of answering anyway.
void main() {
  final monday = DateTime(2026, 5, 4);

  /// A window built from a known truth: the food raised glucose by
  /// `carbs * isf / icr`, the insulin lowered it by `insulin * isf`, and what is
  /// left over is the drift the analysis gets to see.
  TuningDose window({
    required double carbs,
    required double insulin,
    double isf = 50,
    double icr = 10,
    double noise = 0,
  }) {
    final drift = carbs * isf / icr - insulin * isf + noise;
    return TuningDose(
      at: monday,
      carbsAbsorbed: carbs,
      insulinActing: insulin,
      startMgdl: 120,
      endMgdl: 120 + drift.round(),
      minutesToEnd: 300,
      isCorrection: false,
    );
  }

  /// Meals dosed the way people actually dose them: the carbohydrate part plus a
  /// correction for wherever glucose happened to be, rounded to the pump's step.
  List<TuningDose> realisticWeeks({int count = 30, double isf = 50}) {
    final random = Random(7);
    return [
      for (var meal = 0; meal < count; meal++)
        () {
          final carbs = 30 + random.nextInt(60).toDouble();
          final correction = (random.nextInt(9) - 4) * 0.5;
          final insulin =
              ((carbs / 10 + correction) * 20).round() / 20;
          return window(
            carbs: carbs,
            insulin: insulin,
            isf: isf,
            noise: random.nextInt(21) - 10,
          );
        }(),
    ];
  }

  test('it recovers the factor the windows were built from', () {
    final perUnit = CorrectionFactorFit(realisticWeeks()).mgdlPerUnit;

    expect(perUnit, isNotNull);
    expect(perUnit!, closeTo(50, 6));
  });

  /// The case that must be refused rather than answered: every dose is exactly
  /// the carbohydrates divided by the ratio, so the two columns are multiples of
  /// each other and no fit can tell which of them moved the glucose.
  test('it refuses a log where insulin only ever follows the carbohydrates', () {
    final windows = [
      for (var meal = 0; meal < 40; meal++)
        window(carbs: 20 + meal.toDouble(), insulin: (20 + meal) / 10),
    ];

    expect(CorrectionFactorFit(windows).mgdlPerUnit, isNull);
  });

  /// Noise without a real signal must not be read as one either.
  test('it refuses windows whose scatter swamps the answer', () {
    final random = Random(3);
    final windows = [
      for (var meal = 0; meal < 40; meal++)
        window(
          carbs: 50,
          insulin: 5,
          noise: (random.nextInt(201) - 100).toDouble(),
        ),
    ];

    expect(CorrectionFactorFit(windows).mgdlPerUnit, isNull);
  });

  test('a handful of meals is never enough for a fit', () {
    expect(
      CorrectionFactorFit(realisticWeeks(count: CorrectionFactorFit.minWindows - 1))
          .mgdlPerUnit,
      isNull,
    );
  });

  group('what the card is offered', () {
    /// A correction dose is a direct measurement and outranks the fit.
    test('corrections are used when there are any', () {
      final corrections = [
        for (var dose = 0; dose < 6; dose++)
          TuningDose(
            at: monday,
            carbsAbsorbed: 0,
            insulinActing: 2,
            startMgdl: 220,
            endMgdl: 140,
            minutesToEnd: 240,
            minutesToLowest: 240,
            isCorrection: true,
          ),
      ];

      final suggestion = const FactorSuggestions(
        correctionFactor: 35,
        carbFactor: 10,
        insulinDurationH: 3,
      ).correction([...corrections, ...realisticWeeks()]);

      expect(suggestion!.measured, isTrue);
      expect(suggestion.suggested, 40);
    });

    /// The answer for a log with no correction dose in it: inferred, marked as
    /// inferred, and still held to the same 20 % cap.
    test('meals alone give an inferred suggestion', () {
      final suggestion = const FactorSuggestions(
        correctionFactor: 35,
        carbFactor: 10,
        insulinDurationH: 3,
      ).correction(realisticWeeks());

      expect(suggestion!.measured, isFalse);
      expect(suggestion.suggested, 50, reason: 'the truth the windows carry');
      expect(suggestion.samples, 30);
    });
  });
}
