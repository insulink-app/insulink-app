import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/nutrition/nutrition_sync.dart';

/// The pulls REPLACE a collection with the account's copy, and the nutrition pull
/// now runs on every entry to the tab. A meal logged seconds earlier is still
/// queued behind its 3 s debounce, so the account's answer never saw it —
/// adopting it would drop the meal.
void main() {
  tearDown(NutritionSync.cancelPending);

  test('an untouched collection adopts the account copy', () {
    expect(NutritionSync().localWins('meals'), isFalse);
  });

  test('a queued push makes the local copy win', () {
    NutritionSync().pushMeals();
    expect(NutritionSync().localWins('meals'), isTrue);
  });

  test('the guard is per collection, not global', () {
    NutritionSync().pushMeals();
    expect(NutritionSync().localWins('meals'), isTrue);
    expect(NutritionSync().localWins('drinks'), isFalse);
    expect(NutritionSync().localWins('products'), isFalse);
  });

  test('every pushed collection guards its own pull', () {
    NutritionSync()
      ..pushMeals()
      ..pushDrinks()
      ..pushProducts();
    for (final collection in ['meals', 'drinks', 'products']) {
      expect(
        NutritionSync().localWins(collection),
        isTrue,
        reason: '$collection must not be overwritten while its push is queued',
      );
    }
  });

  test('cancelling the queued pushes releases the guard', () {
    NutritionSync().pushMeals();
    NutritionSync.cancelPending();
    expect(NutritionSync().localWins('meals'), isFalse);
  });
}
