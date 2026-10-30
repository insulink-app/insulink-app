import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/service/advisory_action.dart';
import 'package:insulink/src/injection/pending_meal_bolus.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';

PendingMealBolus _photographedAgo(Duration age, {double bolus = 2.5}) {
  final takenAt = DateTime.now().subtract(age);
  return PendingMealBolus(
    takenAt: takenAt,
    meal: Meal(
      time: takenAt,
      carbs: 60,
      glucoseMgdl: 120,
      bolus: bolus,
      entries: const [],
    ),
  );
}

void main() {
  test('is due only after the wait, and only once', () {
    expect(_photographedAgo(const Duration(seconds: 30)).isDue, isFalse);
    final due = _photographedAgo(PendingMealBolus.remindAfter);
    expect(due.isDue, isTrue);
    expect(due.markedWarned().isDue, isFalse);
  });

  test('lapses with the offer, measured from the photo', () {
    expect(_photographedAgo(AdvisoryRequest.validFor * 2).isLapsed, isTrue);
    expect(_photographedAgo(PendingMealBolus.remindAfter).isLapsed, isFalse);
  });

  test('offers a dose the pod can deliver exactly', () {
    expect(
      _photographedAgo(Duration.zero, bolus: 1.01502045).units,
      closeTo(1.0, 0.0001),
    );
  });

  test('survives the trip through storage', () {
    final stored = _photographedAgo(Duration.zero).markedWarned();
    final read = PendingMealBolus.parse(stored.encode())!;

    expect(read.takenAt, stored.takenAt.copyWith(microsecond: 0));
    expect(read.meal.carbs, 60);
    expect(read.meal.bolus, 2.5);
    expect(read.warned, isTrue);
  });

  test('a record nobody can read is no record', () {
    expect(PendingMealBolus.parse(null), isNull);
    expect(PendingMealBolus.parse('not json'), isNull);
    expect(PendingMealBolus.parse('{"taken_at":"noon"}'), isNull);
  });

  test('the meal button parses as a bolus that is tied to its meal', () {
    final request = AdvisoryRequest.parse('$mealBolusAction:2.5:120:1')!;
    expect(request.isBolus, isTrue);
    expect(request.isMealBolus, isTrue);
    expect(AdvisoryRequest.parse('bolus:2.5:120:1')!.isMealBolus, isFalse);
  });
}
