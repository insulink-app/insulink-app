import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// What the server's model reckons is on a photographed plate: a dish name and
/// the WHOLE pictured portion in grams with its nutrients as totals, not per
/// 100 g (`insulink-api` `docs/MEAL_PHOTO_ESTIMATE.md`).
///
/// A guess, never a dose input on its own: [product] turns it into a product
/// for the editor, where the user checks it first.
class PhotoEstimate {
  const PhotoEstimate({
    required this.name,
    required this.grams,
    required this.carbs,
    required this.fat,
    required this.protein,
    required this.kcal,
  });

  /// The model waits on the server for up to 45 s, plus the upload; well above
  /// the 10 s every other request gets.
  static const _timeout = Duration(seconds: 60);

  final String name;
  final double grams;
  final double carbs;
  final double fat;
  final double protein;
  final double kcal;

  factory PhotoEstimate.fromJson(Map<String, dynamic> json) => PhotoEstimate(
    name: json['name'] as String? ?? '',
    grams: (json['grams'] as num?)?.toDouble() ?? 0,
    carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
    fat: (json['fat'] as num?)?.toDouble() ?? 0,
    protein: (json['protein'] as num?)?.toDouble() ?? 0,
    kcal: (json['kcal'] as num?)?.toDouble() ?? 0,
  );

  /// Sends the [jpeg] to the server and reads its estimate. Null when the
  /// request failed or the server had none (no token, usage limit, timeout).
  static Future<PhotoEstimate?> request(
    BuildContext context,
    Uint8List jpeg,
  ) async {
    final response = await Request.post(
      url: '/nutrition/estimate/',
      body: {'image': base64Encode(jpeg), 'language': Locales.lang},
      timeout: _timeout,
    ).send(context);
    final json = response?.jsonObject;
    if (json == null || !response!.isApiSuccess) {
      return null;
    }
    return PhotoEstimate.fromJson(json);
  }

  /// A model that saw no food answers with a zero portion.
  bool get hasFood => grams > 0;

  /// The estimate as a product whose one serving IS the photographed portion,
  /// so the portion sheet offers "1 serving" and the carb math stays the one
  /// every other product uses. Per-100 values are rounded to one decimal for
  /// the editor fields.
  FoodProduct product(String servingLabel) => FoodProduct(
    barcode: '',
    name: name,
    brand: '',
    unit: 'g',
    servingSize: grams,
    servingLabel: servingLabel,
    carbs100g: _per100(carbs),
    fat100g: _per100(fat),
    protein100g: _per100(protein),
    kcal100g: _per100(kcal),
  );

  double _per100(double total) => (total / grams * 1000).round() / 10;
}
