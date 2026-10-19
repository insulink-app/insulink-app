import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/photo_estimate.dart';
import 'package:insulink/src/injection/photo_estimate_item.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';

/// The server's reply is read as it stands: totals for the whole plate plus one
/// item per food. A reply without a portion (the demo backend, a photo without
/// food) must not pass as an estimate of zero carbohydrates.
void main() {
  final estimate = PhotoEstimate.fromJson({
    'name': 'Brot mit Banane',
    'grams': 165,
    'carbs': 44,
    'items': [
      {
        'name': 'Mischbrot',
        'grams': 45,
        'carbs': 19,
        'protein': 3,
        'fat': 0.5,
        'kcal': 95,
      },
      {
        'name': 'Banane',
        'grams': 120,
        'carbs': 25,
        'protein': 1.3,
        'fat': 0.2,
        'kcal': 107,
      },
    ],
    'photo_id': 'abc',
  });

  test('the reply is read as totals plus one item per food', () {
    expect(estimate.carbs, 44);
    expect(estimate.items.map((item) => item.name), ['Mischbrot', 'Banane']);
    expect(estimate.hasFood, isTrue);
  });

  test('every food becomes a meal entry that keeps the photo id', () {
    final entries = estimate.entries();
    expect(entries.map((entry) => entry.carbs), [19, 25]);
    expect(entries.map((entry) => entry.protein), [3, 1.3]);
    expect(entries.every((entry) => entry.photoId == 'abc'), isTrue);
    expect(MealEntry.fromJson(entries.first.toJson()).photoId, 'abc');
  });

  test('a meal from the photo knows its fat, energy and photo', () {
    final meal = Meal(
      time: DateTime(2026, 10, 16, 12),
      carbs: 44,
      glucoseMgdl: 120,
      bolus: 4,
      entries: estimate.entries(),
    );
    expect(meal.kcal, 202);
    expect(meal.fat, closeTo(0.7, 0.001));
    expect(meal.photoId, 'abc');
    final typed = Meal(
      time: DateTime(2026, 10, 16, 12),
      carbs: 44,
      glucoseMgdl: 120,
      bolus: 4,
      entries: const [],
    );
    expect(typed.kcal, isNull);
    expect(typed.photoId, isNull);
  });

  test('a zero portion means the model saw no food', () {
    expect(PhotoEstimate.fromJson({'success': true}).hasFood, isFalse);
  });

  test('the list puts most carbohydrates first and folds small ones', () {
    final plate = PhotoEstimate.fromJson({
      'grams': 400,
      'items': [
        {'name': 'Salat', 'grams': 80, 'carbs': 2, 'protein': 1},
        {'name': 'Mischbrot', 'grams': 45, 'carbs': 19, 'protein': 3},
        {'name': 'Butter', 'grams': 10, 'carbs': 0, 'protein': 0},
        {'name': 'Banane', 'grams': 120, 'carbs': 25, 'protein': 1.3},
      ],
    });
    final summary = plate.summary('Sonstiges');
    expect(summary.map((item) => item.name), [
      'Banane',
      'Mischbrot',
      'Sonstiges',
    ]);
    expect(summary.last.carbs, 2);
    expect(summary.last.grams, 90);
    expect(plate.entries(), hasLength(4));
  });

  test('without small foods there is no "Sonstiges" row', () {
    expect(estimate.summary('Sonstiges').map((item) => item.name), [
      'Banane',
      'Mischbrot',
    ]);
  });

  test('recounting a food scales it and the totals, other foods stay', () {
    final toast = PhotoEstimate.fromJson({
      'name': 'Toast mit Makronen',
      'grams': 90,
      'carbs': 48,
      'items': [
        {'name': 'Toast', 'count': 2, 'grams': 50, 'carbs': 24, 'kcal': 130},
        {'name': 'Kokosmakrone', 'count': 2, 'grams': 40, 'carbs': 24},
      ],
    });
    final corrected = toast.recounted(toast.items.first, 4);
    expect(corrected.items.first.count, 4);
    expect(corrected.items.first.grams, 100);
    expect(corrected.items.first.kcal, 260);
    expect(corrected.items.last.carbs, 24);
    expect(corrected.carbs, 72);
    expect(corrected.grams, 140);
  });

  test('a reply without a count offers no counter', () {
    expect(estimate.items.any((item) => item.countable), isFalse);
    expect(
      PhotoEstimateItem.combined('Sonstiges', estimate.items).countable,
      isFalse,
    );
  });
}
