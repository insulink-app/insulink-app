import 'dart:collection';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/profile/tuning/factor_suggestion.dart';
import 'package:insulink/src/profile/tuning/tuning_dose.dart';
import 'package:insulink/src/profile/tuning/tuning_glucose.dart';
import 'package:insulink/src/profile/tuning/tuning_hour.dart';
import 'package:insulink/src/profile/tuning/tuning_model.dart';

/// The bug that made both suggestions answer "not enough data" whatever window
/// was picked: the archive is keyed by the minute a reading ACTUALLY happened,
/// the analyses ask at hour boundaries, and a sensor on a five-minute cadence
/// almost never lands on one.
void main() {
  final monday = DateTime(2026, 5, 4);

  /// A real archive: a reading every five minutes, on the sensor's own phase.
  SplayTreeMap<int, int> archiveOf({
    required int days,
    int offsetMinutes = 2,
    int mgdl = 120,
  }) {
    final archive = SplayTreeMap<int, int>();
    final start = monday.add(Duration(minutes: offsetMinutes));
    for (var step = 0; step < days * 24 * 12; step++) {
      final at = start.add(Duration(minutes: step * 5));
      archive[at.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute] =
          mgdl;
    }
    return archive;
  }

  test('a reading a few minutes off the asked moment still answers', () {
    final glucose = TuningGlucose(archiveOf(days: 1));

    expect(glucose.at(monday.add(const Duration(hours: 3))), 120);
    expect(glucose.at(monday.add(const Duration(hours: 3, minutes: 4))), 120);
  });

  test('a real hole still reads as missing', () {
    final archive = archiveOf(days: 1);
    final gapFrom = monday.add(const Duration(hours: 3));
    archive.removeWhere((minute, _) {
      final at = DateTime.fromMillisecondsSinceEpoch(
          minute * Duration.millisecondsPerMinute);
      return at.isAfter(gapFrom) &&
          at.isBefore(gapFrom.add(const Duration(minutes: 40)));
    });

    expect(TuningGlucose(archive).at(gapFrom.add(const Duration(minutes: 20))),
        isNull);
  });

  /// The symptom, end to end: with an exact-minute lookup this found four hours
  /// a day at best, and every proposal said there was not enough data.
  test('a week of ordinary readings yields every hour of it', () {
    final glucose = TuningGlucose(archiveOf(days: 7));

    final hours = const TuningHourFinder(
      model: TuningModel(insulinDuration: Duration(hours: 3)),
    ).find(
      from: monday,
      to: monday.add(const Duration(days: 7)),
      meals: const [],
      glucoseAt: glucose.at,
      automationExcessAt: (_) => 0,
    );

    expect(hours, hasLength(7 * 24));
  });

  /// The same symptom on the dose side: three logged meals a day for a week is
  /// plenty of evidence, and the exact-minute lookup found none of it.
  test('an ordinary week of meals yields a carbohydrate factor', () {
    final glucose = TuningGlucose(archiveOf(days: 7));
    final meals = [
      for (var day = 0; day < 7; day++)
        for (final hour in [8, 13, 19])
          Meal(
            time: monday.add(Duration(days: day, hours: hour)),
            carbs: 60,
            glucoseMgdl: 120,
            bolus: 4,
            entries: const [],
          ),
    ];

    final doses = TuningDoseFinder(
      model: const TuningModel(insulinDuration: Duration(hours: 3)),
    ).find(
      from: monday,
      to: monday.add(const Duration(days: 7)),
      meals: meals,
      glucoseAt: glucose.at,
      automationExcessAt: (_) => 0,
    );

    expect(doses, hasLength(21));
    // Glucose ended where it started, so 60 g on the 4 U that acted is the
    // measurement: 15 g per unit, which is what the setting already says.
    const settings = FactorSuggestions(
      correctionFactor: 35,
      carbFactor: 15,
      insulinDurationH: 3,
    );
    expect(settings.carb(doses)!.suggested, 15);
  });

  /// The insulin duration off ordinary meals, with the sensor's own jitter on
  /// top: the answer for somebody who never boluses without eating. The curve
  /// underneath rises for 90 minutes and is back at baseline after four hours,
  /// so four hours is the truth the median has to find.
  test('a noisy fortnight of meals measures the insulin duration', () {
    final random = Random(11);
    final meals = [
      for (var day = 0; day < 14; day++)
        for (final hour in [8, 13, 19])
          Meal(
            time: monday.add(Duration(days: day, hours: hour)),
            carbs: 60,
            glucoseMgdl: 120,
            bolus: 4,
            entries: const [],
          ),
    ];
    double curve(DateTime at) {
      var value = 110.0;
      for (final meal in meals) {
        final minutes = at.difference(meal.time).inMinutes;
        if (minutes < 0 || minutes > 240) {
          continue;
        }
        value += minutes <= 90 ? 70 * minutes / 90 : 70 * (240 - minutes) / 150;
      }
      return value;
    }

    final archive = SplayTreeMap<int, int>();
    final start = monday.add(const Duration(minutes: 2));
    for (var step = 0; step < 14 * 24 * 12; step++) {
      final at = start.add(Duration(minutes: step * 5));
      archive[at.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute] =
          (curve(at) + random.nextInt(9) - 4).round();
    }

    final doses = TuningDoseFinder(
      model: const TuningModel(insulinDuration: Duration(hours: 3)),
    ).find(
      from: monday,
      to: monday.add(const Duration(days: 14)),
      meals: meals,
      glucoseAt: TuningGlucose(archive).at,
      automationExcessAt: (_) => 0,
    );

    final withAnEnd = doses.where((dose) => dose.minutesToLowest != null);
    expect(withAnEnd.length, greaterThan(doses.length - 5),
        reason: 'nearly every meal window is readable');
    const settings = FactorSuggestions(
      correctionFactor: 35,
      carbFactor: 15,
      insulinDurationH: 3,
    );
    expect(settings.duration(doses)!.suggested, 4);
  });
}
