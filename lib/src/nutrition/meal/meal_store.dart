import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'meal.dart';

/// Persistence for the meal log: a JSON list in secure storage, loaded once into
/// [MealState]. Same shape as the food-product store.
class MealStore {
  static const _kMeals = 'nutrition.meals';

  final FlutterSecureStorage _storage;

  const MealStore([this._storage = const FlutterSecureStorage()]);

  Future<List<Meal>> loadMeals() async {
    final raw = await _storage.read(key: _kMeals);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(Meal.fromJson)
        .toList();
  }

  Future<void> saveMeals(List<Meal> meals) => _storage.write(
    key: _kMeals,
    value: jsonEncode(meals.map((meal) => meal.toJson()).toList()),
  );
}
