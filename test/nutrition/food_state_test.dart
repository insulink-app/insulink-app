import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:insulink/src/nutrition/food/food_store.dart';

import '../support/secure_storage_mock.dart';

/// The barcode is a product's identity, so a re-scan has to resolve to the entry
/// the user already corrected instead of starting a second one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  FoodProduct product(String barcode, {String name = 'Müsli', double carbs = 60}) =>
      FoodProduct(
        barcode: barcode,
        name: name,
        brand: '',
        unit: 'g',
        servingSize: null,
        servingLabel: '',
        carbs100g: carbs,
        fat100g: 0,
        protein100g: 0,
        kcal100g: 0,
      );

  test('a scanned barcode resolves to the stored product', () async {
    final state = FoodState(const FoodStore(), []);
    await state.addProduct(product('40111213', carbs: 58));
    final found = state.findByBarcode('40111213');
    expect(found, isNotNull);
    expect(found!.carbs100g, 58);
    expect(state.contains('40111213'), isTrue);
  });

  test('an unknown barcode resolves to nothing', () async {
    final state = FoodState(const FoodStore(), []);
    await state.addProduct(product('40111213'));
    expect(state.findByBarcode('99999999'), isNull);
    expect(state.contains('99999999'), isFalse);
  });

  test('saving the same barcode again replaces rather than duplicates', () async {
    final state = FoodState(const FoodStore(), []);
    await state.addProduct(product('40111213', carbs: 60));
    await state.addProduct(product('40111213', carbs: 58));
    expect(state.products.length, 1);
    expect(state.findByBarcode('40111213')!.carbs100g, 58);
  });
}
