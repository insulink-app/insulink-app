import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// What the server's model reckons is on a photographed plate: a short meal
/// name, every food on it as a [PhotoEstimateItem], and the whole plate's
/// weight and carbohydrates as totals (`insulink-api`
/// `docs/MEAL_PHOTO_ESTIMATE.md`).
///
/// A guess, never a dose input on its own: the bolus calculator puts the
/// carbohydrates into the editable carbs field and lists the foods under it, so
/// an oversized portion shows at a glance.
class PhotoEstimate {
  const PhotoEstimate({
    required this.name,
    required this.grams,
    required this.carbs,
    required this.items,
    this.photoId,
  });

  /// The model waits on the server for up to 45 s, plus the upload; well above
  /// the 10 s every other request gets.
  static const _timeout = Duration(seconds: 60);

  final String name;
  final double grams;
  final double carbs;
  final List<PhotoEstimateItem> items;

  /// The id the server stored the photo under; travels on the meal entries.
  final String? photoId;

  factory PhotoEstimate.fromJson(Map<String, dynamic> json) => PhotoEstimate(
    name: json['name'] as String? ?? '',
    grams: (json['grams'] as num?)?.toDouble() ?? 0,
    carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
    items: [
      for (final item in json['items'] as List? ?? const [])
        PhotoEstimateItem.fromJson(item as Map<String, dynamic>),
    ],
    photoId: json['photo_id'] as String?,
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

  /// A model that saw no food answers with no items and a zero portion.
  bool get hasFood => grams > 0;

  /// Below this many grams of carbohydrates a food is not worth its own row.
  static const _minorCarbs = 5.0;

  /// The foods as the calculator lists them: most carbohydrates first, and
  /// everything under [_minorCarbs] folded into one row named [otherName] at
  /// the end, weights and carbohydrates summed. Only the list is shortened; the
  /// meal still logs every food on its own ([entries]).
  List<PhotoEstimateItem> summary(String otherName) {
    final major = [
      for (final item in items)
        if (item.carbs >= _minorCarbs) item,
    ]..sort((first, second) => second.carbs.compareTo(first.carbs));
    final minor = [
      for (final item in items)
        if (item.carbs < _minorCarbs) item,
    ];
    if (minor.isEmpty) {
      return major;
    }
    return [...major, PhotoEstimateItem.combined(otherName, minor)];
  }

  /// One meal entry per food, like products picked from the database, so their
  /// protein reaches the day's nutrition totals and the meal log lists them.
  /// Each carries [photoId], so any of them opens the photo again.
  List<MealEntry> entries() => [
    for (final item in items)
      MealEntry(
        name: item.name,
        unit: 'g',
        amount: item.grams,
        carbs: item.carbs,
        protein: item.protein,
        photoId: photoId,
      ),
  ];
}

/// One food on the photographed plate: its edible weight and the
/// carbohydrates and protein of that weight, in grams.
class PhotoEstimateItem {
  const PhotoEstimateItem({
    required this.name,
    required this.grams,
    required this.carbs,
    required this.protein,
  });

  final String name;
  final double grams;
  final double carbs;
  final double protein;

  /// Several foods as one, their weights and nutrients summed.
  factory PhotoEstimateItem.combined(
    String name,
    List<PhotoEstimateItem> parts,
  ) => PhotoEstimateItem(
    name: name,
    grams: parts.fold(0, (sum, part) => sum + part.grams),
    carbs: parts.fold(0, (sum, part) => sum + part.carbs),
    protein: parts.fold(0, (sum, part) => sum + part.protein),
  );

  factory PhotoEstimateItem.fromJson(Map<String, dynamic> json) =>
      PhotoEstimateItem(
        name: json['name'] as String? ?? '',
        grams: (json['grams'] as num?)?.toDouble() ?? 0,
        carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
        protein: (json['protein'] as num?)?.toDouble() ?? 0,
      );
}
