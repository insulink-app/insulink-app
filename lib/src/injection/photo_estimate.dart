import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:insulink/src/injection/photo_estimate_item.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// What the server's model reckons is on a photographed plate: a short meal
/// name, every food on it as a [PhotoEstimateItem], and the whole plate's
/// weight and carbohydrates as totals (`insulink-api`
/// `docs/MEAL_PHOTO_ESTIMATE.md`).
///
/// A guess: the bolus calculator puts the carbohydrates into the editable carbs
/// field and lists the foods under it, so an oversized portion shows at a
/// glance. The one dose that can go out without that page is the missed-meal
/// warning's button, whose notification names the carbs instead
/// ([PendingMealBolus]).
class PhotoEstimate {
  const PhotoEstimate({
    required this.name,
    required this.grams,
    required this.carbs,
    required this.items,
    this.photoId,
  });

  /// The model runs on the server for up to 120 s (a branded product is looked
  /// up on the web), behind a 150 s proxy, plus the upload; well above the 10 s
  /// every other request gets.
  static const _timeout = Duration(seconds: 160);

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
  /// [runId] names the run for a cancel, and [abortTrigger] drops the request
  /// (see `PhotoEstimateRun`).
  static Future<PhotoEstimate?> request(
    BuildContext context,
    Uint8List jpeg, {
    required String runId,
    required Future<void> abortTrigger,
  }) async {
    final response = await Request.post(
      url: '/nutrition/estimate/',
      body: {
        'image': base64Encode(jpeg),
        'language': Locales.lang,
        'run_id': runId,
      },
      timeout: _timeout,
      abortTrigger: abortTrigger,
    ).send(context);
    final json = response?.jsonObject;
    if (json == null || !response!.isApiSuccess) {
      return null;
    }
    return PhotoEstimate.fromJson(json);
  }

  /// The estimate with [item] counted as [count] pieces instead, the totals
  /// following, so the carbs field and the logged entries match the corrected
  /// plate.
  PhotoEstimate recounted(PhotoEstimateItem item, int count) {
    final recountedItems = [
      for (final each in items)
        identical(each, item) ? each.recounted(count) : each,
    ];
    return PhotoEstimate(
      name: name,
      grams: recountedItems.fold(0, (sum, each) => sum + each.grams),
      carbs: recountedItems.fold(0, (sum, each) => sum + each.carbs),
      items: recountedItems,
      photoId: photoId,
    );
  }

  /// A model that saw no food answers with no items and a zero portion.
  bool get hasFood => grams > 0;

  /// Below this many grams of carbohydrates a food is not worth its own row.
  static const _minorCarbs = 5.0;

  /// The foods worth a row of their own, most carbohydrates first.
  List<PhotoEstimateItem> get major => [
    for (final item in items)
      if (item.carbs >= _minorCarbs) item,
  ]..sort((first, second) => second.carbs.compareTo(first.carbs));

  /// The foods under [_minorCarbs], folded into "Sonstiges" by the calculator.
  List<PhotoEstimateItem> get minor => [
    for (final item in items)
      if (item.carbs < _minorCarbs) item,
  ];

  /// The foods as one list: [major], then [minor] folded into one row named
  /// [otherName] at the end, weights and carbohydrates summed. Only the list is
  /// shortened; the meal still logs every food on its own ([entries]).
  List<PhotoEstimateItem> summary(String otherName) {
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
        fat: item.fat,
        kcal: item.kcal,
        photoId: photoId,
      ),
  ];
}
