import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  test('a fresh state has no drinks and a zero-progress bar', () async {
    final state = await NutritionState.load();

    expect(state.entries, isEmpty);
    expect(state.todayEntries, isEmpty);
    expect(state.todayMl, 0);
    expect(state.todayFraction, 0);
  });

  test('drinks logged today count toward the goal', () async {
    final state = await NutritionState.load();
    await state.setGoalLitres(2);

    await state.addDrink(500, 'water');
    await state.addDrink(250, 'tea');

    expect(state.todayMl, 750);
    expect(state.todayEntries.length, 2);
    expect(state.todayFraction, closeTo(0.375, 0.001));
  });

  test('the progress bar caps at a full goal', () async {
    final state = await NutritionState.load();
    await state.setGoalLitres(0.5);

    await state.addDrink(2000, 'water');

    expect(state.todayFraction, 1);
  });

  test('removing a drink takes it back out of the total', () async {
    final state = await NutritionState.load();
    await state.addDrink(500, 'water');

    await state.removeEntry(state.entries.single);

    expect(state.todayMl, 0);
  });

  test('the goals clamp to their allowed range', () async {
    final state = await NutritionState.load();

    await state.setGoalLitres(99);
    await state.setCarbsGoalG(5);
    await state.setProteinGoalG(9999);

    expect(state.goalLitres, 10);
    expect(state.carbsGoalG, 20);
    expect(state.proteinGoalG, 400);
  });

  test('an unchanged goal notifies nobody', () async {
    final state = await NutritionState.load();
    await state.setCarbsGoalG(180);
    var notifications = 0;
    state.addListener(() => notifications++);

    await state.setCarbsGoalG(180);
    expect(notifications, 0);

    await state.setCarbsGoalG(200);
    expect(notifications, 1);
  });

  test('goals and drinks survive a reload of the same instance', () async {
    final state = await NutritionState.load();
    await state.setGoalLitres(3);
    await state.setProteinGoalG(120);
    await state.addDrink(300, 'water');

    await state.reload();

    expect(state.goalLitres, 3);
    expect(state.proteinGoalG, 120);
    expect(state.entries.single.ml, 300);
  });

  test('the entry list is unmodifiable from the outside', () async {
    final state = await NutritionState.load();

    expect(() => state.entries.clear(), throwsUnsupportedError);
  });
}
