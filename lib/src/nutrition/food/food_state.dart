import 'package:flutter/foundation.dart';

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

  /// Products newest first (most recently scanned on top).
  List<FoodProduct> get products => _products.reversed.toList();

  bool contains(String barcode) =>
      _products.any((product) => product.barcode == barcode);

  /// Adds a product, replacing any existing entry with the same barcode so a
  /// re-scan refreshes rather than duplicates.
  Future<void> addProduct(FoodProduct product) async {
    _products.removeWhere((existing) => existing.barcode == product.barcode);
    _products.add(product);
    notifyListeners();
    await _store.saveProducts(_products);
  }

  Future<void> removeProduct(FoodProduct product) async {
    _products.removeWhere((existing) => existing.barcode == product.barcode);
    notifyListeners();
    await _store.saveProducts(_products);
  }
}
