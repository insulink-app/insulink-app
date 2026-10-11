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
import 'package:insulink/src/request/response_json.dart';
import 'package:insulink/src/request/sync_ledger.dart';

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
  static const _ledger = SyncLedger();

  /// The storage keys this pull rewrites, assembled from the three stores it
  /// touches — the set [SyncReload] watches to skip a no-op sync's rebuild.
  static const syncedKeys = <String>[
    ...MealStore.syncedKeys,
    ...NutritionStore.syncedKeys,
    ...FoodStore.syncedKeys,
  ];

  /// Collections whose local change has not reached the backend yet — the
  /// debounce is still armed, or its POST is in flight. See [localWins].
  static final Set<String> _unsent = {};

  // ---- push (debounced per collection) ----

  void pushMeals() => _debounce('meals', _sendMeals);
  void pushDrinks() => _debounce('drinks', _sendDrinks);
  void pushProducts() => _debounce('products', _sendProducts);

  /// Marks [key] unsent in the [SyncLedger] until the account accepts the push,
  /// so a failed one is merged on the next pull instead of reverted.
  void _debounce(String key, Future<bool> Function() send) {
    _timers[key]?.cancel();
    _unsent.add(key);
    unawaited(_ledger.mark(_ledgerKey(key)));
    _timers[key] = Timer(const Duration(seconds: 3), () async {
      try {
        if (await send()) {
          await _ledger.clear(_ledgerKey(key));
        }
      } finally {
        _unsent.remove(key);
      }
    });
  }

  String _ledgerKey(String collection) => 'nutrition.$collection';

  /// Whether the local copy of [collection] must win over a pull response.
  ///
  /// Mirrors `SportSync.localWins`, and matters more here: [pull] now runs on
  /// every entry to the nutrition tab, so a meal logged seconds ago is regularly
  /// still queued (3 s debounce) when the account's answer — which never saw it —
  /// comes back to replace the local list.
  @visibleForTesting
  bool localWins(String collection) => _unsent.contains(collection);

  /// Cancels any armed pushes — for tests, so a mutation's debounce timer does
  /// not outlive the test as a pending timer.
  @visibleForTesting
  static void cancelPending() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _unsent.clear();
  }

  Future<bool> _post(String url, Map<String, Object> body) async {
    final response = await Request.post(url: url, body: body).send(null);
    return response.isApiSuccess;
  }

  Future<bool> _sendMeals() async {
    final meals = await _mealStore.loadMeals();
    return _post('/nutrition/meals/sync/', {
      'meals': meals.map((meal) => meal.toJson()).toList(),
    });
  }

  Future<bool> _sendDrinks() async {
    final drinks = await _drinkStore.loadEntries();
    return _post('/nutrition/drinks/sync/', {
      'drinks': drinks.map((drink) => drink.toJson()).toList(),
    });
  }

  Future<bool> _sendProducts() async {
    final products = await _productStore.loadProducts();
    return _post('/nutrition/products/sync/', {
      'products': products.map((product) => product.toJson()).toList(),
    });
  }

  // ---- pull all on sign-in ----

  /// Adopts the account's nutrition data into the local stores (on sign-in and on
  /// every cold start), so a returning device shows its full history. Each
  /// collection is replaced with the server's, which is the source of truth,
  /// unless the [SyncLedger] holds an unconfirmed local change: then the two are
  /// merged and pushed back.
  ///
  /// The three fetches run concurrently — they write separate collections, and a
  /// cold start waits on this (see [AccountSync]).
  Future<void> pull(BuildContext? context) async {
    await Future.wait([
      _pullMeals(context),
      _pullDrinks(context),
      _pullProducts(context),
    ]);
  }

  /// GETs [url] and returns its [key] list, or null when there is nothing safe to
  /// adopt — an unusable response, or one the server answered without a local
  /// change it hasn't been told about yet ([localWins] on [collection]). Every
  /// caller already skips its overwrite on null, so the guard lives here.
  Future<List<dynamic>?> _fetch(
    BuildContext? context,
    String url,
    String key,
    String collection,
  ) async {
    final response = await Request.get(url: url).send(context);
    if (localWins(collection)) {
      return null;
    }
    final body = response.jsonObject;
    if (body == null) {
      return null;
    }
    if (body['success'] != true || body[key] is! List) {
      return null;
    }
    return body[key] as List<dynamic>;
  }

  Future<void> _pullMeals(BuildContext? context) async {
    final list = await _fetch(
      context,
      '/nutrition/meals/find/',
      'meals',
      'meals',
    );
    if (list == null) {
      return;
    }
    final merged = await _ledger.adopt(
      collection: _ledgerKey('meals'),
      remote: [for (final item in list) Meal.fromJson((item as Map).cast())],
      local: _mealStore.loadMeals,
      save: _mealStore.saveMeals,
      keyOf: (meal) => jsonEncode(meal.toJson()),
    );
    if (merged) {
      pushMeals();
    }
  }

  Future<void> _pullDrinks(BuildContext? context) async {
    final list = await _fetch(
      context,
      '/nutrition/drinks/find/',
      'drinks',
      'drinks',
    );
    if (list == null) {
      return;
    }
    final merged = await _ledger.adopt(
      collection: _ledgerKey('drinks'),
      remote: [
        for (final item in list) DrinkEntry.fromJson((item as Map).cast()),
      ],
      local: _drinkStore.loadEntries,
      save: _drinkStore.saveEntries,
      keyOf: (drink) => jsonEncode(drink.toJson()),
    );
    if (merged) {
      pushDrinks();
    }
  }

  Future<void> _pullProducts(BuildContext? context) async {
    final list = await _fetch(
      context,
      '/nutrition/products/find/',
      'products',
      'products',
    );
    if (list == null) {
      return;
    }
    final merged = await _ledger.adopt(
      collection: _ledgerKey('products'),
      remote: [
        for (final item in list) FoodProduct.fromJson((item as Map).cast()),
      ],
      local: _productStore.loadProducts,
      save: _productStore.saveProducts,
      keyOf: (product) => jsonEncode(product.toJson()),
    );
    if (merged) {
      pushProducts();
    }
  }
}
