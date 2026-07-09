import 'dart:convert';

import 'package:http/http.dart' as http;

import 'food_product.dart';

/// Looks up a scanned barcode in the free Open Food Facts database (no API key).
/// Returns the product with its per-100 g nutrition, or null when the barcode is
/// unknown or the request fails.
class OffClient {
  const OffClient();

  static const _base = 'https://world.openfoodfacts.org/api/v2/product';
  // OFF asks every client to identify itself in the User-Agent.
  static const _userAgent = 'Insulink - Android - Version 1.0';

  Future<FoodProduct?> lookup(String barcode) async {
    final uri = Uri.parse(
      '$_base/$barcode.json?fields=product_name,brands,nutriments',
    );
    final response = await http.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) {
      return null;
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['status'] != 1 || json['product'] is! Map) {
      return null;
    }
    return _parse(barcode, json['product'] as Map<String, dynamic>);
  }

  FoodProduct _parse(String barcode, Map<String, dynamic> product) {
    final nutriments = product['nutriments'] as Map<String, dynamic>? ?? {};
    return FoodProduct(
      barcode: barcode,
      name: (product['product_name'] as String? ?? '').trim(),
      brand: (product['brands'] as String? ?? '').trim(),
      carbs100g: _grams(nutriments['carbohydrates_100g']),
      fat100g: _grams(nutriments['fat_100g']),
      protein100g: _grams(nutriments['proteins_100g']),
      kcal100g: _grams(nutriments['energy-kcal_100g']),
    );
  }

  double _grams(dynamic value) => value is num ? value.toDouble() : 0;
}
