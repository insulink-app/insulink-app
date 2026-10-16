import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/photo_estimate.dart';
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
      {'name': 'Mischbrot', 'grams': 45, 'carbs': 19, 'protein': 3},
      {'name': 'Banane', 'grams': 120, 'carbs': 25, 'protein': 1.3},
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

  test('a zero portion means the model saw no food', () {
    expect(PhotoEstimate.fromJson({'success': true}).hasFood, isFalse);
  });
}
