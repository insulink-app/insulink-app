import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  Meal mealAt(DateTime time, {double carbs = 30, double bolus = 3}) => Meal(
    time: time,
    carbs: carbs,
    glucoseMgdl: 110,
    bolus: bolus,
    entries: const [
      MealEntry(name: 'Bread', unit: 'g', amount: 100, carbs: 30, protein: 5),
    ],
  );

  test('meals are listed newest first', () async {
    final state = await MealState.load();
    final older = mealAt(DateTime(2026, 7, 8, 9));
    final newer = mealAt(DateTime(2026, 7, 9, 9));

    await state.addMeal(older);
    await state.addMeal(newer);

    expect(state.meals, [newer, older]);
  });

  test("today's totals count only meals logged since midnight", () async {
    final state = await MealState.load();
    final now = DateTime.now();

    await state.addMeal(mealAt(now.subtract(const Duration(days: 2))));
    await state.addMeal(
      mealAt(DateTime(now.year, now.month, now.day, 8), carbs: 40, bolus: 4),
    );
    await state.addMeal(
      mealAt(DateTime(now.year, now.month, now.day, 12), carbs: 20, bolus: 2),
    );

    expect(state.todayCount, 2);
    expect(state.todayCarbs, 60);
    expect(state.todayBolus, 6);
    expect(state.todayProtein, 10);
  });

  test('an edit replaces the exact instance and survives a reload', () async {
    final state = await MealState.load();
    final logged = mealAt(DateTime(2026, 7, 9, 9));
    await state.addMeal(logged);

    await state.updateMeal(logged, logged.copyWith(carbs: 55));
    expect(state.meals.single.carbs, 55);

    await state.updateMeal(mealAt(DateTime(2026, 1, 1)), logged);
    expect(state.meals.single.carbs, 55, reason: 'an unknown meal is a no-op');

    await state.reload();
    expect(state.meals.single.carbs, 55);
  });

  test('removing a meal drops it from the store', () async {
    final state = await MealState.load();
    final logged = mealAt(DateTime(2026, 7, 9, 9));
    await state.addMeal(logged);

    await state.removeMeal(logged);
    await state.reload();

    expect(state.meals, isEmpty);
  });

  test('a confirmed bolus still lands after a sync pull replaced the log', () async {
    final state = await MealState.load();
    final logged = mealAt(DateTime.now(), bolus: 0);
    await state.addMeal(logged);

    // What the bolus dispatcher lives through: the pod is still answering while
    // a pull rebuilds every meal in the list from storage.
    await state.reload();

    expect(await state.updateMeal(logged, logged.copyWith(bolus: 2.2)), isTrue);
    await state.reload();
    expect(state.meals.single.bolus, 2.2);
  });

  test('updating a meal that is gone reports that it did not land', () async {
    final state = await MealState.load();
    final logged = mealAt(DateTime(2026, 7, 9, 9));
    await state.addMeal(logged);
    await state.removeMeal(logged);

    expect(await state.updateMeal(logged, logged.copyWith(bolus: 2.2)), isFalse);
  });

  test('the log is capped, dropping the oldest meals', () async {
    final state = await MealState.load();

    for (var index = 0; index < 205; index++) {
      await state.addMeal(mealAt(DateTime(2026, 1, 1).add(Duration(hours: index))));
    }

    expect(state.meals.length, 200);
    expect(state.meals.last.time, DateTime(2026, 1, 1, 5));
  });
}
