import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/profile/tuning/factor_suggestion.dart';
import 'package:insulink/src/profile/tuning/tuning_dose.dart';
import 'package:insulink/src/profile/tuning/tuning_model.dart';

/// The same danger as the basal tuning, one layer over: a factor learned from a
/// window whose insulin and food were not accounted for is a bolus calculator
/// quietly handing somebody the wrong number for every meal after it. Nothing is
/// discarded for being busy any more, so what keeps it honest is that the other
/// insulin and the other food in the window are measured into the arithmetic.
void main() {
  final monday = DateTime(2026, 5, 4, 3);

  Meal dose(DateTime time, {double carbs = 0, double bolus = 0}) => Meal(
        time: time,
        carbs: carbs,
        glucoseMgdl: 0,
        bolus: bolus,
        entries: const [],
      );

  /// Glucose that falls by [perHour] from [start] and then stays there, which is
  /// what a correction looks like when it has finished working.
  int? Function(DateTime) fallingFrom(
    DateTime at,
    int start,
    int perHour, {
    Duration over = const Duration(hours: 4),
  }) {
    return (moment) {
      final minutes = moment.difference(at).inMinutes;
      final capped = minutes > over.inMinutes ? over.inMinutes : minutes;
      return start - (capped * perHour / 60).round();
    };
  }

  const finder = TuningDoseFinder(
    model: TuningModel(insulinDuration: Duration(hours: 3)),
  );

  List<TuningDose> found({
    required List<Meal> meals,
    required int? Function(DateTime) glucose,
    double automation = 0,
  }) {
    return finder.find(
      from: monday.subtract(const Duration(days: 1)),
      to: monday.add(const Duration(days: 30)),
      meals: meals,
      glucoseAt: glucose,
      automationExcessAt: (_) => automation,
    );
  }

  group('what a dose window carries', () {
    /// 2 U took glucose from 220 to 140 over four hours: the plain case the
    /// whole analysis is built on.
    test('a lone correction is measured to its lowest point', () {
      final doses = found(
        meals: [dose(monday, bolus: 2)],
        glucose: fallingFrom(monday, 220, 20),
      );

      expect(doses, hasLength(1));
      expect(doses.single.isCorrection, isTrue);
      expect(doses.single.endMgdl, 140);
      expect(doses.single.minutesToEnd, 240);
      expect(doses.single.insulinActing, closeTo(2, 1e-9));
    });

    /// The change the user asked for: insulin still working from an earlier dose
    /// used to disqualify the window. It is now part of what acted in it, so the
    /// fall is credited to all of the insulin rather than to this dose alone.
    test('insulin from an earlier dose is counted into the window', () {
      final doses = found(
        meals: [
          dose(monday.subtract(const Duration(hours: 1)), bolus: 3),
          dose(monday, bolus: 2),
        ],
        glucose: fallingFrom(monday, 220, 20),
      );

      // 2 U of its own, plus the two thirds of the earlier 3 U that had not yet
      // acted when this one was given.
      final own = doses.firstWhere((dose) => dose.at == monday);
      expect(own.insulinActing, closeTo(4, 1e-9));
    });

    /// A meal in the window no longer kills it: the window is cut short at the
    /// food, because carbohydrates hide the fall this is measuring.
    test('food ends a correction window rather than voiding it', () {
      final doses = found(
        meals: [
          dose(monday, bolus: 2),
          dose(monday.add(const Duration(hours: 3)), carbs: 40, bolus: 3),
        ],
        glucose:
            fallingFrom(monday, 220, 40, over: const Duration(hours: 2)),
      );

      expect(doses, hasLength(2), reason: 'the meal is its own window');
      final correction = doses.firstWhere((dose) => dose.isCorrection);
      expect(correction.minutesToEnd, 120);
      expect(correction.carbsAbsorbed, 0);
    });

    /// Food arriving before there is any fall to read leaves nothing to measure.
    test('food too soon after a correction drops it', () {
      final doses = found(
        meals: [
          dose(monday, bolus: 2),
          dose(monday.add(const Duration(hours: 1)), carbs: 40),
        ],
        glucose: fallingFrom(monday, 220, 20),
      );

      expect(doses.where((dose) => dose.isCorrection), isEmpty);
    });

    /// The automation's insulin is insulin. It is counted into the window, so
    /// its effect is not credited to the dose.
    test('automated insulin is counted, not a disqualification', () {
      final doses = found(
        meals: [dose(monday, bolus: 2)],
        glucose: fallingFrom(monday, 220, 20),
        automation: 0.3,
      );

      expect(doses.single.insulinActing, greaterThan(2));
    });

    /// Counter-regulation stops the fall down there, so the measured drop is
    /// smaller than the insulin caused. A factor learned from it would claim
    /// insulin is weaker than it is, which is the one direction that must not
    /// happen.
    test('a correction that ended in a hypo is dropped', () {
      final doses = found(
        meals: [dose(monday, bolus: 3)],
        glucose: fallingFrom(monday, 220, 45),
      );

      expect(doses, isEmpty);
    });

    /// Glucose still falling when the window ran out understates the dose, which
    /// is the same wrong direction.
    test('a fall still going at the end of the window is dropped', () {
      final doses = found(
        meals: [dose(monday, bolus: 2)],
        glucose: fallingFrom(monday, 220, 8, over: const Duration(hours: 12)),
      );

      expect(doses, isEmpty);
    });

    /// Insulin given at a normal glucose is not a correction, whatever it was
    /// logged as.
    test('a correction from a normal glucose is dropped', () {
      final doses = found(
        meals: [dose(monday, bolus: 2)],
        glucose: fallingFrom(monday, 130, 10),
      );

      expect(doses, isEmpty);
    });

    /// A hole in the readings can hide the true lowest point.
    test('a window with too few readings is dropped', () {
      final doses = found(
        meals: [dose(monday, bolus: 2)],
        glucose: (moment) => moment.difference(monday).inMinutes > 60
            ? null
            : fallingFrom(monday, 220, 20)(moment),
      );

      expect(doses, isEmpty);
    });
  });

  group('what the windows suggest', () {
    const settings = FactorSuggestions(
      correctionFactor: 35,
      carbFactor: 15,
      insulinDurationH: 3,
    );

    TuningDose correction({
      required int start,
      required int end,
      required double insulin,
      int minutes = 240,
    }) =>
        TuningDose(
          at: monday,
          carbsAbsorbed: 0,
          insulinActing: insulin,
          startMgdl: start,
          endMgdl: end,
          minutesToEnd: minutes,
          minutesToLowest: minutes,
          isCorrection: true,
        );

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
          startMgdl: 120,
          endMgdl: 120 + drift,
          minutesToEnd: 300,
          minutesToLowest: minutesToLowest,
          isCorrection: false,
        );

    List<TuningDose> repeated(TuningDose dose, int times) =>
        List<TuningDose>.filled(times, dose);

    /// Silence is the honest answer to four windows.
    test('too few windows say nothing', () {
      expect(
        settings.correction(
            repeated(correction(start: 220, end: 140, insulin: 2), 4)),
        isNull,
      );
    });

    /// 80 mg/dL for the 2 U that acted is 40 mg/dL per unit, and the setting
    /// says 35.
    test('the correction factor follows the measured drop', () {
      final suggestion = settings.correction(
          repeated(correction(start: 220, end: 140, insulin: 2), 6));

      expect(suggestion!.suggested, 40);
      expect(suggestion.samples, 6);
    });

    /// One wild window must not carry a setting, which is what the median is
    /// for.
    test('an outlier window does not move the factor', () {
      final doses = [
        ...repeated(correction(start: 220, end: 150, insulin: 2), 5),
        correction(start: 250, end: 80, insulin: 1),
      ];

      expect(settings.correction(doses)!.suggested, 35);
    });

    /// The proposal IS the measurement. There used to be a cap of a fifth per
    /// run, and it held nothing back: pressing the button three times walked to
    /// the same number anyway, which is what made the analysis look like it kept
    /// changing its mind.
    test('a far-off measurement is offered in full', () {
      final suggestion = settings.correction(
          repeated(correction(start: 250, end: 100, insulin: 1), 6));

      expect(suggestion!.suggested, 100, reason: '150 mg/dL for one unit');
    });

    /// A window that landed back where it started had its carbohydrates covered
    /// exactly by the insulin that acted: 60 g on 3 U is 20 g per unit.
    test('the carbohydrate factor comes from a window that landed flat', () {
      final suggestion =
          settings.carb(repeated(mealWindow(carbs: 60, insulin: 3), 6));

      expect(suggestion!.suggested, 20, reason: '60 g on the 3 U that acted');
    });

    /// A window that ended high needed more insulin than acted in it, so the
    /// ratio is measured against that larger dose and comes out smaller.
    test('a window that drifted up tightens the ratio', () {
      final flat = settings.carb(repeated(mealWindow(carbs: 60, insulin: 3), 6))!;
      final drifted = settings
          .carb(repeated(mealWindow(carbs: 60, insulin: 3, drift: 70), 6))!;

      expect(drifted.suggested, lessThan(flat.suggested));
    });

    /// Below that the estimate of the food itself is the biggest term in the
    /// arithmetic.
    test('a window with barely any food says nothing about the ratio', () {
      expect(settings.carb(repeated(mealWindow(carbs: 10, insulin: 1), 6)),
          isNull);
    });

    /// The measured length of the action, not a guess: four hours to the lowest
    /// point, against a setting of three.
    test('the insulin duration follows the time to the lowest point', () {
      final suggestion = settings
          .duration(repeated(correction(start: 220, end: 140, insulin: 2), 6));

      expect(suggestion!.suggested, 4);
    });

    /// The answer for somebody who always boluses with food: the end of a meal's
    /// fall is the same event as the end of a correction's, so the setting is
    /// measurable without a single correction dose.
    test('meal windows measure the insulin duration too', () {
      final suggestion = settings.duration(
          repeated(mealWindow(carbs: 60, insulin: 4, minutesToLowest: 250), 6));

      expect(suggestion!.suggested, 4);
    });

    /// A window whose fall could not be followed to its end says nothing about
    /// the duration.
    test('a window with no readable end says nothing about the duration', () {
      expect(settings.duration(repeated(mealWindow(carbs: 60, insulin: 4), 6)),
          isNull);
    });

    /// The reported symptom, gone: one press lands on the answer and the next
    /// press has nothing left to change.
    test('one press lands on the answer', () {
      final windows =
          repeated(correction(start: 220, end: 140, insulin: 2), 6);

      final first = const FactorSuggestions(
        correctionFactor: 30,
        carbFactor: 15,
        insulinDurationH: 3,
      ).correction(windows)!;
      expect(first.suggested, 40, reason: 'what the doses said, in one go');

      final second = FactorSuggestions(
        correctionFactor: first.suggested,
        carbFactor: 15,
        insulinDurationH: 3,
      ).correction(windows)!;
      expect(second.isChange, isFalse);
    });

    /// Nothing may leave the range the setting itself allows.
    test('a proposal stays inside the setting range', () {
      final suggestion = settings.duration(repeated(
          correction(start: 220, end: 140, insulin: 2, minutes: 60), 6));

      expect(suggestion!.suggested, greaterThanOrEqualTo(2));
    });
  });
}
