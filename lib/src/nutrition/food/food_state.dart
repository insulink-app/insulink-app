import 'package:flutter/foundation.dart';

import '../nutrition_sync.dart';
import 'food_product.dart';
import 'food_store.dart';

/// The scanned-product database: products the user has added by scanning a
/// barcode. Pattern like [SportState] — static [load], mutate → [notifyListeners]
/// → persist.
class FoodState extends ChangeNotifier {
  final FoodStore _store;
  final List<FoodProduct> _products;

  FoodState(this._store, this._products);

  static Future<FoodState> load() async {
    const store = FoodStore();
    return FoodState(store, await store.loadProducts());
  }

  /// Re-read the store into THIS instance, so a pull that replaced the stored
  /// products reaches the UI. See [MealState.reload].
  Future<void> reload() async {
    final fresh = await FoodState.load();
    _products
      ..clear()
      ..addAll(fresh._products);
    notifyListeners();
  }

  /// Products newest first (most recently scanned on top).
  List<FoodProduct> get products => _products.reversed.toList();

  bool contains(String barcode) => findByBarcode(barcode) != null;

  /// The stored product for [barcode], or null when it has never been scanned.
  /// The barcode is the product's identity here (see [addProduct]), so this is
  /// what a re-scan resolves to instead of creating a second entry.
  FoodProduct? findByBarcode(String barcode) {
    for (final product in _products) {
      if (product.barcode == barcode) {
        return product;
      }
    }
    return null;
  }

  /// Adds a product, replacing any existing entry with the same barcode so a
  /// re-scan refreshes rather than duplicates.
  Future<void> addProduct(FoodProduct product) async {
    _products.removeWhere((existing) => existing.barcode == product.barcode);
    _products.add(product);
    notifyListeners();
    await _store.saveProducts(_products);
    NutritionSync().pushProducts();
  }

  Future<void> removeProduct(FoodProduct product) async {
    _products.removeWhere((existing) => existing.barcode == product.barcode);
    notifyListeners();
    await _store.saveProducts(_products);
    NutritionSync().pushProducts();
  }
}
