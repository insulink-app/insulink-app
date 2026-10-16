import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/nutrition/food/photo_estimate.dart';

/// The server answers with totals for the whole plate; the editor and the
/// portion sheet work per 100 g with a serving. One serving must give back the
/// estimated carbohydrates, or the dose would be computed from other numbers
/// than the ones the model gave.
void main() {
  final estimate = PhotoEstimate.fromJson({
    'name': 'Spaghetti Bolognese',
    'grams': 350,
    'carbs': 72,
    'fat': 14,
    'protein': 18,
    'kcal': 490,
  });

  test('one serving of the product is the photographed portion', () {
    final product = estimate.product('Portion vom Foto');
    expect(product.servingSize, 350);
    expect(product.unit, 'g');
    expect(product.servingLabel, 'Portion vom Foto');
    expect(product.carbs100g * product.servingSize! / 100, closeTo(72, 0.2));
    expect(product.kcal100g, 140);
  });

  test('a zero portion means the model saw no food', () {
    expect(estimate.hasFood, isTrue);
    expect(PhotoEstimate.fromJson({'success': true}).hasFood, isFalse);
  });
}
