import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';

void main() {
  final time = DateTime(2026, 7, 9, 12, 30);

  MealEntry entry({double protein = 0, double? serving}) => MealEntry(
    name: 'Bread',
    unit: 'g',
    amount: 100,
    carbs: 45,
    protein: protein,
    servingSize: serving,
  );

  test('protein sums the logged products and is 0 for a manual entry', () {
    final logged = Meal(
      time: time,
      carbs: 90,
      glucoseMgdl: 120,
      bolus: 6,
      entries: [entry(protein: 8), entry(protein: 4.5)],
    );
    final manual = Meal(
      time: time, carbs: 30, glucoseMgdl: 100, bolus: 2, entries: const []);

    expect(logged.protein, 12.5);
    expect(manual.protein, 0);
  });

  test('servings need a declared serving size', () {
    expect(entry(serving: 40).servings, 2.5);
    expect(entry(serving: 0).servings, isNull);
    expect(entry().servings, isNull);
  });

  test('copyWith replaces only the given fields and keeps the entries', () {
    final meal = Meal(
      time: time,
      carbs: 90,
      glucoseMgdl: 120,
      bolus: 6,
      entries: [entry()],
    );

    final edited = meal.copyWith(carbs: 50, glucoseMgdl: 140);

    expect(edited.carbs, 50);
    expect(edited.glucoseMgdl, 140);
    expect(edited.time, time);
    expect(edited.bolus, 6);
    expect(edited.entries, same(meal.entries));
  });

  test('json round-trip keeps the meal and its entries', () {
    final meal = Meal(
      time: time,
      carbs: 90,
      glucoseMgdl: 120,
      bolus: 6.5,
      entries: [
        const MealEntry(
          barcode: '4001234',
          name: 'Bread',
          unit: 'g',
          amount: 100,
          carbs: 45,
          protein: 8,
          servingSize: 50,
        ),
      ],
    );

    final restored = Meal.fromJson(meal.toJson());

    expect(restored.time, time);
    expect(restored.carbs, 90);
    expect(restored.glucoseMgdl, 120);
    expect(restored.bolus, 6.5);
    expect(restored.entries.single.barcode, '4001234');
    expect(restored.entries.single.servingSize, 50);
    expect(restored.entries.single.protein, 8);
  });

  test('a legacy json defaults the missing entry fields', () {
    final restored = Meal.fromJson({
      'time': time.millisecondsSinceEpoch,
      'carbs': 30,
      'glucose': 100,
      'bolus': 2,
      'entries': [
        {'name': 'Apple', 'amount': 120, 'carbs': 14},
      ],
    });

    expect(restored.entries.single.unit, 'g');
    expect(restored.entries.single.barcode, '');
    expect(restored.entries.single.protein, 0);
    expect(restored.entries.single.servingSize, isNull);
  });

  test('a json without entries parses as a manual carb entry', () {
    final restored = Meal.fromJson({
      'time': time.millisecondsSinceEpoch,
      'carbs': 30,
      'glucose': 100,
      'bolus': 2,
    });

    expect(restored.entries, isEmpty);
    expect(restored.protein, 0);
  });
}
