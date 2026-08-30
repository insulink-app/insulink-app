import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/profile/tuning/basal_suggestion.dart';
import 'package:insulink/src/profile/tuning/tuning_hour.dart';
import 'package:insulink/src/profile/tuning/tuning_model.dart';

/// The danger this feature has to keep bounded: attributing a glucose rise to
/// basal when a meal, a bolus or the automation caused it. It no longer refuses
/// such hours outright, so what keeps a forgotten biscuit from becoming a
/// night-time hypoglycaemia is that the other causes are MEASURED and taken off
/// first, and that whatever is left is capped and taken as a median.
void main() {
  final monday = DateTime(2026, 5, 4);

  Meal meal(DateTime time, {double carbs = 0, double bolus = 0}) => Meal(
        time: time,
        carbs: carbs,
        glucoseMgdl: 0,
        bolus: bolus,
        entries: const [],
      );

  TuningHour hourWith({
    required DateTime start,
    required int fromMgdl,
    required int toMgdl,
    double carbsAbsorbed = 0,
    double insulinActing = 0,
  }) =>
      TuningHour(
        start: start,
        fromMgdl: fromMgdl,
        toMgdl: toMgdl,
        carbsAbsorbed: carbsAbsorbed,
        insulinActing: insulinActing,
      );

  const finder = TuningHourFinder(
    model: TuningModel(insulinDuration: Duration(hours: 3)),
  );

  /// Glucose that rises steadily, so every hour drifts by [perHour].
  int? Function(DateTime) risingFrom(int start, int perHour) {
    return (moment) =>
        start + (moment.difference(monday).inMinutes * perHour / 60).round();
  }

  List<TuningHour> nights({
    required List<Meal> meals,
    int perHour = 10,
    double automation = 0,
    int days = 5,
  }) {
    return finder.find(
      from: monday.add(const Duration(hours: 2)),
      to: monday.add(Duration(days: days, hours: 5)),
      meals: meals,
      glucoseAt: risingFrom(120, perHour),
      automationExcessAt: (_) => automation,
    );
  }

  group('an hour carries what else was acting in it', () {
    test('a quiet hour carries nothing', () {
      final hours = nights(meals: const []);

      expect(hours, isNotEmpty);
      expect(hours.every((hour) => hour.carbsAbsorbed == 0), isTrue);
      expect(hours.every((hour) => hour.insulinActing == 0), isTrue);
    });

    /// The change the user asked for: a meal used to disqualify the four hours
    /// after it. Now the grams absorbed in each of them are measured, and the
    /// hour is kept.
    test('a meal is measured into the hours it feeds, not thrown away', () {
      final hours = nights(
        meals: [meal(monday.add(const Duration(hours: 2)), carbs: 40)],
      );

      final fed = hours.where((hour) =>
          hour.start.day == monday.day &&
          hour.start.hour >= 2 &&
          hour.start.hour < 6);

      expect(fed, hasLength(4));
      // 40 g over the four-hour absorption is 10 g in each of them.
      expect(fed.every((hour) => (hour.carbsAbsorbed - 10).abs() < 1e-9), isTrue);
    });

    /// A bolus is the same story, over the insulin duration rather than the
    /// absorption time.
    test('a bolus is measured into the hours it works through', () {
      final hours = nights(
        meals: [meal(monday.add(const Duration(hours: 2)), bolus: 3)],
      );

      final working = hours.where((hour) =>
          hour.start.day == monday.day &&
          hour.start.hour >= 2 &&
          hour.start.hour < 5);

      expect(working, hasLength(3));
      expect(working.every((hour) => (hour.insulinActing - 1).abs() < 1e-9),
          isTrue);
    });

    /// Insulin the automation added is insulin. It is counted like a bolus,
    /// spread over the same duration.
    test('automated insulin is counted, not a disqualification', () {
      final hours = nights(meals: const [], automation: 0.3);

      expect(hours, isNotEmpty);
      expect(hours.every((hour) => (hour.insulinActing - 0.3).abs() < 1e-9),
          isTrue);
    });

    /// Below and above these the body's own counter-regulation is doing
    /// something no basal rate explains.
    test('hours outside the plausible glucose range are dropped', () {
      final tooLow = finder.find(
        from: monday,
        to: monday.add(const Duration(hours: 6)),
        meals: const [],
        glucoseAt: (_) => 55,
        automationExcessAt: (_) => 0,
      );
      final tooHigh = finder.find(
        from: monday,
        to: monday.add(const Duration(hours: 6)),
        meals: const [],
        glucoseAt: (_) => 300,
        automationExcessAt: (_) => 0,
      );

      expect(tooLow, isEmpty);
      expect(tooHigh, isEmpty);
    });

    /// An hour missing a reading at either end is dropped rather than guessed
    /// at, because a guessed drift becomes a real basal change.
    test('a gap in the readings drops the hour', () {
      final hours = finder.find(
        from: monday,
        to: monday.add(const Duration(hours: 6)),
        meals: const [],
        glucoseAt: (moment) => moment.hour == 3 ? null : 120,
        automationExcessAt: (_) => 0,
      );

      expect(hours.any((hour) => hour.start.hour == 3), isFalse);
      expect(hours.any((hour) => hour.start.hour == 2), isFalse,
          reason: 'the hour ENDING at the gap is unusable too');
    });
  });

  /// The window used to be clipped to the moment the automation record began,
  /// which is the first time the loop was ever switched on. Somebody who turned
  /// it on last week therefore got last week however many months they asked for,
  /// and every proposal said there was not enough data. Nothing could have been
  /// running before that moment, so there is nothing to clear.
  group('the age of the automation record does not clip the window', () {
    List<TuningHour> over(int days) => finder.find(
          from: monday,
          to: monday.add(Duration(days: days)),
          meals: const [],
          glucoseAt: (_) => 120,
          automationExcessAt: (_) => 0,
        );

    test('a long window is a long window', () {
      expect(over(5).length, 5 * 24);
      expect(over(30).length, 30 * 24);
    });
  });

  group('what the hours suggest', () {
    final suggest = BasalSuggestion(
      correctionFactor: 50,
      carbFactor: 10,
      currentRates: List<double>.filled(24, 1.0),
    );

    List<TuningHour> nightly({
      required int drift,
      double carbsAbsorbed = 0,
      double insulinActing = 0,
      int days = 4,
    }) =>
        [
          for (var day = 0; day < days; day++)
            hourWith(
              start: monday.add(Duration(days: day, hours: 3)),
              fromMgdl: 120,
              toMgdl: 120 + drift,
              carbsAbsorbed: carbsAbsorbed,
              insulinActing: insulinActing,
            ),
        ];

    /// Glucose rising 10 mg/dL in an hour at a factor of 50 means 0.2 U of
    /// insulin was missing from that hour.
    test('a steady rise asks for more basal', () {
      final hour = suggest.from(nightly(drift: 10)).single;

      expect(hour.hour, 3);
      expect(hour.suggested, closeTo(1.2, 1e-9));
      expect(hour.samples, 4);
    });

    test('a steady fall asks for less', () {
      expect(suggest.from(nightly(drift: -10)).single.suggested,
          closeTo(0.8, 1e-9));
    });

    /// The point of the whole change: an hour that rose because food was being
    /// absorbed says nothing about the basal rate, and now says so by measuring
    /// the food rather than by being discarded. 10 g at 10 g per unit is one
    /// unit, which at a factor of 50 is exactly the 50 mg/dL observed.
    test('a rise the food explains asks for no change', () {
      final hour = suggest.from(nightly(drift: 50, carbsAbsorbed: 10)).single;

      expect(hour.suggested, closeTo(1.0, 1e-9));
      expect(hour.isChange, isFalse);
    });

    /// The mirror case: glucose held flat while a bolus was working means the
    /// basal underneath it was short by exactly that insulin.
    test('insulin that held an hour flat is credited back', () {
      final hour = suggest.from(nightly(drift: 0, insulinActing: 0.2)).single;

      expect(hour.suggested, closeTo(1.2, 1e-9));
    });

    /// The last refusal: when the model carries more than it can be trusted to,
    /// the answer would be arithmetic about absorption timing rather than a
    /// reading.
    test('an hour the model dominates is dropped', () {
      expect(suggest.from(nightly(drift: 10, carbsAbsorbed: 30)), isEmpty);
      expect(suggest.from(nightly(drift: 10, insulinActing: 3)), isEmpty);
    });

    /// Silence is the honest answer for an hour with too little behind it.
    test('too few hours say nothing at all', () {
      expect(
        suggest.from(
          nightly(drift: 40, days: BasalSuggestion.minSamples - 1),
        ),
        isEmpty,
      );
    });

    /// One bad night must not carry an hour, so the middle value decides.
    test('a single outlier night does not move the hour', () {
      final hours = [
        ...nightly(drift: 2),
        hourWith(
          start: monday.add(const Duration(days: 4, hours: 3)),
          fromMgdl: 120,
          toMgdl: 220,
        ),
      ];

      final hour = suggest.from(hours).single;

      expect(hour.medianDrift, 2);
      expect(hour.suggested, closeTo(1.05, 1e-9));
    });
  });

  /// The reported symptom: adopt a proposal, press again, get another one, and
  /// the basal walks away. The drift was measured under the OLD rates, so
  /// putting it on top of rates that already carry it counts it twice.
  group('hours only count while the schedule they ran under is running', () {
    test('a schedule that changed mid-window cuts the hours before it', () {
      final changedAt = monday.add(const Duration(days: 3));

      final hours = finder.find(
        from: monday,
        to: monday.add(const Duration(days: 5)),
        meals: const [],
        glucoseAt: (_) => 120,
        automationExcessAt: (_) => 0,
      );
      final afterChange =
          hours.where((hour) => !hour.start.isBefore(changedAt)).toList();

      expect(hours.length, 5 * 24);
      expect(afterChange.length, 2 * 24,
          reason: 'the card starts the window at the change');
    });

    /// Adopting a proposal and pressing again must not repeat it. With the
    /// hours before the change gone there is nothing left to repeat it FROM.
    test('nothing is left to say right after a change', () {
      final suggest = BasalSuggestion(
        correctionFactor: 50,
        carbFactor: 10,
        currentRates: List<double>.filled(24, 1.2),
      );

      expect(suggest.from(const []), isEmpty);
    });
  });

  group('a proposal can only ever move a rate a little', () {
    final suggest = BasalSuggestion(
      correctionFactor: 50,
      carbFactor: 10,
      currentRates: List<double>.filled(24, 1.0),
    );

    List<TuningHour> drifting(int drift) => [
          for (var day = 0; day < 4; day++)
            hourWith(
              start: monday.add(Duration(days: day, hours: 3)),
              fromMgdl: 120,
              toMgdl: 120 + drift,
            ),
        ];

    /// A week of nights is thin evidence, and the cost of being wrong is
    /// asymmetric: too much basal at 03:00 is a hypoglycaemia in your sleep.
    test('a wild rise is capped at a fifth of the current rate', () {
      expect(suggest.from(drifting(120)).single.suggested, closeTo(1.2, 1e-9));
    });

    test('a wild fall is capped the same way', () {
      expect(suggest.from(drifting(-120)).single.suggested, closeTo(0.8, 1e-9));
    });

    test('it never proposes a negative rate', () {
      final zeroed = BasalSuggestion(
        correctionFactor: 50,
        carbFactor: 10,
        currentRates: List<double>.filled(24, 0.05),
      );

      expect(zeroed.from(drifting(-500)).single.suggested,
          greaterThanOrEqualTo(0));
    });

    test('every proposal lands on the pump grid', () {
      for (final drift in [3, 7, 11, -3, -7]) {
        final rate = suggest.from(drifting(drift)).single.suggested;

        expect((rate * 20 - (rate * 20).round()).abs(), lessThan(1e-9),
            reason: '$rate is off the 0.05 grid');
      }
    });
  });

  /// The daily total is not held constant. Each hour moves on its own evidence
  /// and the total is whatever the hours add up to, because a profile that gave
  /// too little insulin overnight needs MORE insulin, not the same amount
  /// shuffled around the clock.
  group('the daily amount is free to change', () {
    final suggest = BasalSuggestion(
      correctionFactor: 50,
      carbFactor: 10,
      currentRates: List<double>.filled(24, 1.0),
    );

    List<TuningHour> everyHourDrifting(int drift) => [
          for (var hour = 0; hour < 24; hour++)
            for (var day = 0; day < 4; day++)
              hourWith(
                start: monday.add(Duration(days: day, hours: hour)),
                fromMgdl: 120,
                toMgdl: 120 + drift,
              ),
        ];

    double totalOf(List<HourSuggestion> hours) =>
        hours.fold<double>(0, (sum, hour) => sum + hour.suggested);

    test('a day that ran high suggests more insulin overall', () {
      final total = totalOf(suggest.from(everyHourDrifting(10)));

      expect(total, greaterThan(24));
      expect(total, closeTo(24 * 1.2, 1e-6));
    });

    test('a day that ran low suggests less overall', () {
      final total = totalOf(suggest.from(everyHourDrifting(-10)));

      expect(total, lessThan(24));
      expect(total, closeTo(24 * 0.8, 1e-6));
    });

    /// Only the hours with evidence move, so a profile that drifted for three
    /// hours a night changes by those three hours and not by a whole day.
    test('hours without evidence keep their rate and their share', () {
      final suggestions = suggest.from([
        for (var day = 0; day < 4; day++)
          hourWith(
            start: monday.add(Duration(days: day, hours: 3)),
            fromMgdl: 120,
            toMgdl: 130,
          ),
      ]);

      expect(suggestions, hasLength(1));
      expect(suggestions.single.change, closeTo(0.2, 1e-9));
    });
  });
}
