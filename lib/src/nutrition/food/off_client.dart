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

  static const _fields =
      'product_name,brands,quantity,serving_size,serving_quantity,'
      'serving_quantity_unit,nutriments';

  /// Full-text search by [terms], most-relevant first. Returns up to 20 named
  /// products with their per-100 g nutrition; entries without a name are dropped
  /// (the DB has many sparse stubs). Returns empty on any network/format error.
  ///
  /// Uses the main host's `/api/v2/search` — the dedicated `search.openfoodfacts.org`
  /// host and the classic `cgi/search.pl` both routinely 502/503, so this is the
  /// only reliably-JSON search endpoint.
  Future<List<FoodProduct>> search(String terms) async {
    // The classic cgi/search.pl is the ONLY endpoint that actually ranks by
    // relevance — /api/v2/search's `search_terms` is silently ignored (it
    // returns the whole DB in random order) and search.openfoodfacts.org 502's.
    final uri = Uri.https('world.openfoodfacts.org', '/cgi/search.pl', {
      'search_terms': terms,
      'search_simple': '1',
      'action': 'process',
      'json': '1',
      'page_size': '20',
      'fields': 'code,$_fields',
    });
    // cgi/search.pl intermittently 5xx's / times out; retry a few times before
    // giving up. A 200 with no matches is a real "no results" — only transient
    // failures (non-200 / exception) are retried.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http
            .get(uri, headers: {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          return _parseSearch(response.body);
        }
      } catch (_) {
        // fall through to the backoff + retry
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
    return const [];
  }

  List<FoodProduct> _parseSearch(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final products = json['products'];
    if (products is! List) {
      return const [];
    }
    return [
      for (final entry in products)
        if (entry is Map<String, dynamic>)
          if (_parse(entry['code'] as String? ?? '', entry) case final product
              when product.name.isNotEmpty)
            product,
    ];
  }

  Future<FoodProduct?> lookup(String barcode) async {
    final uri = Uri.parse('$_base/$barcode.json?fields=$_fields');
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
      name: product['product_name'] is String
          ? (product['product_name'] as String).trim()
          : '',
      brand: _brand(product['brands']),
      unit: _unit(product),
      servingSize: _num(product['serving_quantity']),
      servingLabel: (product['serving_size'] as String? ?? '').trim(),
      carbs100g: _grams(nutriments['carbohydrates_100g']),
      fat100g: _grams(nutriments['fat_100g']),
      protein100g: _grams(nutriments['proteins_100g']),
      kcal100g: _grams(nutriments['energy-kcal_100g']),
    );
  }

  /// 'ml' for drinks, 'g' for solids. Trusts OFF's explicit serving unit, else
  /// infers from the quantity/serving text mentioning a volume unit.
  String _unit(Map<String, dynamic> product) {
    final explicit = (product['serving_quantity_unit'] as String? ?? '')
        .toLowerCase();
    if (explicit == 'ml' || explicit == 'g') {
      return explicit;
    }
    final text = '${product['quantity'] ?? ''} ${product['serving_size'] ?? ''}'
        .toLowerCase();
    return RegExp(r'\d\s*(ml|cl|l|litre|liter)\b').hasMatch(text) ? 'ml' : 'g';
  }

  /// Brands come as a comma string from the barcode API but as a list from the
  /// search API.
  String _brand(dynamic value) {
    if (value is String) {
      return value.trim();
    }
    if (value is List) {
      return value.whereType<String>().join(', ').trim();
    }
    return '';
  }

  double _grams(dynamic value) => value is num ? value.toDouble() : 0;

  double? _num(dynamic value) => value is num
      ? value.toDouble()
      : (value is String ? double.tryParse(value) : null);
}
