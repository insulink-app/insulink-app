import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/profile/tuning/basal_suggestion.dart';
import 'package:insulink/src/profile/tuning/clean_hour.dart';

/// The danger this whole feature has to avoid: attributing a glucose rise to
/// basal when a meal, a bolus or the automation caused it. A basal raised
/// because of a forgotten biscuit is a night-time hypoglycaemia days later.
void main() {
  final monday = DateTime(2026, 5, 4);

  Meal meal(DateTime time, {double carbs = 0, double bolus = 0}) => Meal(
        time: time,
        carbs: carbs,
        glucoseMgdl: 0,
        bolus: bolus,
        entries: const [],
      );

  const finder = CleanHourFinder(insulinDuration: Duration(hours: 3));

  /// Glucose that rises steadily, so every hour drifts by [perHour].
  int? Function(DateTime) risingFrom(int start, int perHour) {
    return (moment) =>
        start + (moment.difference(monday).inMinutes * perHour / 60).round();
  }

  List<CleanHour> nights({
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

  group('an hour is dropped unless nothing else can explain it', () {
    test('a clean night is kept', () {
      expect(nights(meals: const []), isNotEmpty);
    });

    /// The forgotten biscuit. Carbs cast a shadow forwards, so the hours after
    /// them are not evidence about basal.
    test('carbohydrates disqualify the hours that follow', () {
      final hours = nights(
        meals: [meal(monday.add(const Duration(hours: 2)), carbs: 30)],
      );

      final touched = hours.where((hour) =>
          hour.start.day == monday.day &&
          hour.start.hour >= 2 &&
          hour.start.hour < 6);
      expect(touched, isEmpty);
    });

    test('a bolus disqualifies the hours it is still working through', () {
      final hours = nights(
        meals: [meal(monday.add(const Duration(hours: 2)), bolus: 3)],
      );

      final touched = hours.where((hour) =>
          hour.start.day == monday.day &&
          hour.start.hour >= 2 &&
          hour.start.hour < 5);
      expect(touched, isEmpty);
    });

    /// Insulin the automation added is insulin, and an hour carrying it says
    /// nothing about what the SCHEDULE should have been.
    test('automated insulin disqualifies an hour', () {
      expect(nights(meals: const [], automation: 0.4), isEmpty);
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

  /// An unanswerable "was the automation running?" reads as "no", and the hour
  /// would then count as evidence about the SCHEDULE even though extra insulin
  /// is what moved its glucose. It would argue for LOWERING a basal rate that
  /// was never the reason.
  group('hours the automation record cannot clear are dropped', () {
    List<CleanHour> over(int days, {DateTime? knownSince}) => finder.find(
          from: monday,
          to: monday.add(Duration(days: days)),
          meals: const [],
          glucoseAt: (_) => 120,
          automationExcessAt: (_) => 0,
          automationKnownSince: knownSince,
        );

    test('with no pump every hour is usable', () {
      expect(over(5).length, 5 * 24);
    });

    /// The ledger holds five days, so a thirty day window is still five days of
    /// answerable hours.
    test('only hours the record reaches are kept', () {
      final since = monday.add(const Duration(days: 3));

      final hours = over(5, knownSince: since);

      expect(hours.every((hour) => !hour.start.isBefore(since)), isTrue);
      expect(hours.length, 2 * 24);
    });

    test('a record that reaches nothing yields nothing', () {
      expect(over(5, knownSince: monday.add(const Duration(days: 9))), isEmpty);
    });
  });

  group('what the clean hours suggest', () {
    final suggest = BasalSuggestion(
      correctionFactor: 50,
      currentRates: List<double>.filled(24, 1.0),
    );

    /// Glucose rising 10 mg/dL in an hour at a factor of 50 means 0.2 U of
    /// insulin was missing from that hour.
    test('a steady rise asks for more basal', () {
      final hours = [
        for (var day = 0; day < 4; day++)
          CleanHour(
            start: monday.add(Duration(days: day, hours: 3)),
            fromMgdl: 120,
            toMgdl: 130,
          ),
      ];

      final hour = suggest.from(hours).single;

      expect(hour.hour, 3);
      expect(hour.suggested, closeTo(1.2, 1e-9));
      expect(hour.samples, 4);
    });

    test('a steady fall asks for less', () {
      final hours = [
        for (var day = 0; day < 4; day++)
          CleanHour(
            start: monday.add(Duration(days: day, hours: 3)),
            fromMgdl: 130,
            toMgdl: 120,
          ),
      ];

      expect(suggest.from(hours).single.suggested, closeTo(0.8, 1e-9));
    });

    /// Silence is the honest answer for an hour nobody has clean data for.
    test('too few clean hours say nothing at all', () {
      final hours = [
        for (var day = 0; day < BasalSuggestion.minSamples - 1; day++)
          CleanHour(
            start: monday.add(Duration(days: day, hours: 3)),
            fromMgdl: 120,
            toMgdl: 160,
          ),
      ];

      expect(suggest.from(hours), isEmpty);
    });

    /// One bad night must not carry an hour, so the middle value decides.
    test('a single outlier night does not move the hour', () {
      final hours = [
        for (var day = 0; day < 4; day++)
          CleanHour(
            start: monday.add(Duration(days: day, hours: 3)),
            fromMgdl: 120,
            toMgdl: 122,
          ),
        CleanHour(
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

  group('a proposal can only ever move a rate a little', () {
    final suggest = BasalSuggestion(
      correctionFactor: 50,
      currentRates: List<double>.filled(24, 1.0),
    );

    List<CleanHour> drifting(int drift) => [
          for (var day = 0; day < 4; day++)
            CleanHour(
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
      currentRates: List<double>.filled(24, 1.0),
    );

    List<CleanHour> everyHourDrifting(int drift) => [
          for (var hour = 0; hour < 24; hour++)
            for (var day = 0; day < 4; day++)
              CleanHour(
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
      final hours = [
        for (var day = 0; day < 4; day++)
          CleanHour(
            start: monday.add(Duration(days: day, hours: 3)),
            fromMgdl: 120,
            toMgdl: 130,
          ),
      ];

      final suggestions = suggest.from(hours);

      expect(suggestions, hasLength(1));
      expect(suggestions.single.change, closeTo(0.2, 1e-9));
    });
  });
}
