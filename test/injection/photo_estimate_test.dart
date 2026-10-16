import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/photo_estimate.dart';

/// The server's reply is read as it stands: totals for the whole plate. A reply
/// without a portion (the demo backend, a photo without food) must not pass as
/// an estimate of zero carbohydrates.
void main() {
  test('the reply is read as totals for the plate', () {
    final estimate = PhotoEstimate.fromJson({
      'name': 'Spaghetti Bolognese',
      'grams': 350,
      'carbs': 72.4,
      'fat': 14,
      'protein': 18,
      'kcal': 490,
    });
    expect(estimate.name, 'Spaghetti Bolognese');
    expect(estimate.carbs, 72.4);
    expect(estimate.hasFood, isTrue);
  });

  test('a zero portion means the model saw no food', () {
    expect(PhotoEstimate.fromJson({'success': true}).hasFood, isFalse);
  });
}
