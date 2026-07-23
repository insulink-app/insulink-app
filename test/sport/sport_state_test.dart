import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:insulink/src/sport/sport_store.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  WeightEntry weightAt(DateTime at, double kg) =>
      WeightEntry(atEpochMs: at.millisecondsSinceEpoch, kg: kg);

  test('a fresh state carries the store defaults and no weight', () async {
    final state = await SportState.load();

    expect(state.weights, isEmpty);
    expect(state.latestWeight, isNull);
    expect(state.bmi, isNull);
    expect(state.strideCm, SportStore.defStrideCm);
    expect(state.heightCm, SportStore.defHeightCm);
    expect(state.stepsGoal, SportStore.defStepsGoal);
    expect(state.distanceGoalKm, SportStore.defDistanceGoalM / 1000);
    expect(state.caloriesGoal, SportStore.defCaloriesGoal);
    expect(state.weightGoalKg, SportStore.defWeightGoalKg);
  });

  test('weights are kept ascending whatever order they arrive in', () async {
    final state = await SportState.load();

    await state.addWeight(80, at: DateTime(2026, 7, 9));
    await state.addWeight(82, at: DateTime(2026, 7, 1));
    await state.addWeight(79, at: DateTime(2026, 7, 5));

    expect(state.weights.map((entry) => entry.kg), [82, 79, 80]);
    expect(state.latestWeight!.kg, 80);
  });

  test('the BMI uses the latest weight and the stored height', () async {
    final state = await SportState.load();
    await state.setHeightCm(180);
    await state.addWeight(81, at: DateTime(2026, 7, 9));

    expect(state.bmi, closeTo(25.0, 0.01));
  });

  test('merging imported weights deduplicates by timestamp', () async {
    final state = await SportState.load();
    final existing = DateTime(2026, 7, 9);
    await state.addWeight(80, at: existing);

    await state.mergeWeights([
      weightAt(existing, 99),
      weightAt(DateTime(2026, 7, 10), 81),
    ]);

    expect(state.weights.map((entry) => entry.kg), [80, 81]);
  });

  test('merging only already-known weights persists nothing', () async {
    final state = await SportState.load();
    final existing = DateTime(2026, 7, 9);
    await state.addWeight(80, at: existing);

    await state.mergeWeights([weightAt(existing, 99)]);

    expect(state.weights.single.kg, 80);
  });

  test('editing replaces the entry and re-sorts by the new time', () async {
    final state = await SportState.load();
    await state.addWeight(80, at: DateTime(2026, 7, 9));
    await state.addWeight(81, at: DateTime(2026, 7, 10));
    final original = state.weights.first;

    await state.editWeight(original, kg: 78, at: DateTime(2026, 7, 11));

    expect(state.weights.map((entry) => entry.kg), [81, 78]);
  });

  test('removing a weight drops it and survives a reload', () async {
    final state = await SportState.load();
    await state.addWeight(80, at: DateTime(2026, 7, 9));

    await state.removeWeight(state.weights.single);
    await state.reload();

    expect(state.weights, isEmpty);
  });

  test('the setters clamp to their allowed range', () async {
    final state = await SportState.load();

    await state.setStrideCm(5);
    await state.setHeightCm(400);
    await state.setStepsGoal(10);
    await state.setDistanceGoalM(1);
    await state.setCaloriesGoal(99999);
    await state.setWeightGoalKg(1);

    expect(state.strideCm, 40);
    expect(state.heightCm, 250);
    expect(state.stepsGoal, 1000);
    expect(state.distanceGoalKm, 0.5);
    expect(state.caloriesGoal, 5000);
    expect(state.weightGoalKg, 30);
  });

  test('setting an unchanged value notifies nobody', () async {
    final state = await SportState.load();
    var notifications = 0;
    state.addListener(() => notifications++);

    await state.setStrideCm(SportStore.defStrideCm);
    await state.setStepsGoal(SportStore.defStepsGoal);
    expect(notifications, 0);

    await state.setStrideCm(90);
    expect(notifications, 1);
  });

  test('the settings are persisted and read back by a second load', () async {
    final state = await SportState.load();
    await state.setStrideCm(88);
    await state.setWeightGoalKg(72.5);
    await state.addWeight(80, at: DateTime(2026, 7, 9));

    final reloaded = await SportState.load();

    expect(reloaded.strideCm, 88);
    expect(reloaded.weightGoalKg, 72.5);
    expect(reloaded.weights.single.kg, 80);
  });

  test('the weight list is unmodifiable from the outside', () async {
    final state = await SportState.load();

    expect(
      () => state.weights.add(weightAt(DateTime(2026, 1, 1), 70)),
      throwsUnsupportedError,
    );
  });
}
