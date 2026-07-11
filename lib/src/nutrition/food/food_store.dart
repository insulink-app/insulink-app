import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'food_product.dart';

/// Persistence for the scanned-product database: a JSON list in secure storage,
/// loaded once into [FoodState]. Same shape as the hydration store.
class FoodStore {
  static const _kProducts = 'nutrition.products';

  final FlutterSecureStorage _storage;

  const FoodStore([this._storage = const FlutterSecureStorage()]);

  Future<List<FoodProduct>> loadProducts() async {
    final raw = await _storage.read(key: _kProducts);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(FoodProduct.fromJson)
        .toList();
  }

  Future<void> saveProducts(List<FoodProduct> products) => _storage.write(
    key: _kProducts,
    value: jsonEncode(products.map((product) => product.toJson()).toList()),
  );
}
