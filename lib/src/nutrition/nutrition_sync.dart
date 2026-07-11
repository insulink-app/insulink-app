import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_store.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_store.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_store.dart';
import 'package:insulink/src/request/request.dart';

/// Mirrors the user's nutrition data (the meal log + logged drinks) to their
/// backend account and pulls it back on sign-in. Same shape as [SportSync]: each
/// `push*` debounces a best-effort replace-all of that one collection; [pull]
/// runs on sign-in and writes the account's data into the store before the
/// provider tree reloads.
class NutritionSync {
  static const _mealStore = MealStore();
  static const _drinkStore = NutritionStore();
  static const _productStore = FoodStore();
  static final Map<String, Timer> _timers = {};

  // ---- push (debounced per collection) ----

  void pushMeals() => _debounce('meals', _sendMeals);
  void pushDrinks() => _debounce('drinks', _sendDrinks);
  void pushProducts() => _debounce('products', _sendProducts);

  void _debounce(String key, Future<void> Function() send) {
    _timers[key]?.cancel();
    _timers[key] = Timer(const Duration(seconds: 3), send);
  }

  /// Cancels any armed pushes — for tests, so a mutation's debounce timer does
  /// not outlive the test as a pending timer.
  @visibleForTesting
  static void cancelPending() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  Future<void> _post(String url, Map<String, Object> body) async {
    await Request.post(url: url, body: body).send(null);
  }

  Future<void> _sendMeals() async {
    final meals = await _mealStore.loadMeals();
    await _post('/nutrition/meals/sync/', {
      'meals': meals.map((meal) => meal.toJson()).toList(),
    });
  }

  Future<void> _sendDrinks() async {
    final drinks = await _drinkStore.loadEntries();
    await _post('/nutrition/drinks/sync/', {
      'drinks': drinks.map((drink) => drink.toJson()).toList(),
    });
  }

  Future<void> _sendProducts() async {
    final products = await _productStore.loadProducts();
    await _post('/nutrition/products/sync/', {
      'products': products.map((product) => product.toJson()).toList(),
    });
  }

  // ---- pull all on sign-in ----

  /// Adopts the account's nutrition data into the local stores (on sign-in), so a
  /// returning device shows its full history. Each collection is replaced with
  /// the server's, which is the source of truth at sign-in.
  Future<void> pull(BuildContext context) async {
    await _pullMeals(context);
    if (!context.mounted) {
      return;
    }
    await _pullDrinks(context);
    if (!context.mounted) {
      return;
    }
    await _pullProducts(context);
  }

  Future<List<dynamic>?> _fetch(
    BuildContext context,
    String url,
    String key,
  ) async {
    final response = await Request.get(url: url).send(context);
    if (response == null) {
      return null;
    }
    final body = jsonDecode(response.body);
    if (body['success'] != true || body[key] is! List) {
      return null;
    }
    return body[key] as List<dynamic>;
  }

  Future<void> _pullMeals(BuildContext context) async {
    final list = await _fetch(context, '/nutrition/meals/find/', 'meals');
    if (list == null) {
      return;
    }
    await _mealStore.saveMeals([
      for (final item in list) Meal.fromJson((item as Map).cast()),
    ]);
  }

  Future<void> _pullDrinks(BuildContext context) async {
    final list = await _fetch(context, '/nutrition/drinks/find/', 'drinks');
    if (list == null) {
      return;
    }
    await _drinkStore.saveEntries([
      for (final item in list) DrinkEntry.fromJson((item as Map).cast()),
    ]);
  }

  Future<void> _pullProducts(BuildContext context) async {
    final list = await _fetch(context, '/nutrition/products/find/', 'products');
    if (list == null) {
      return;
    }
    await _productStore.saveProducts([
      for (final item in list) FoodProduct.fromJson((item as Map).cast()),
    ]);
  }
}
