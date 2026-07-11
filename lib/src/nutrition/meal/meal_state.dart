import 'package:flutter/foundation.dart';

import 'meal.dart';
import 'meal_store.dart';

/// The meal log: meals the user logged when delivering a bolus. Pattern like
/// [FoodState] — static [load], mutate → [notifyListeners] → persist. Capped so
/// the stored list can't grow unbounded.
class MealState extends ChangeNotifier {
  static const _cap = 200;

  final MealStore _store;
  final List<Meal> _meals;

  MealState(this._store, this._meals);

  static Future<MealState> load() async {
    const store = MealStore();
    return MealState(store, await store.loadMeals());
  }

  /// Meals newest first.
  List<Meal> get meals => _meals.reversed.toList();

  /// Meals logged since local midnight.
  List<Meal> get todayMeals {
    final now = DateTime.now();
    final since = DateTime(now.year, now.month, now.day);
    return _meals.where((meal) => meal.time.isAfter(since)).toList();
  }

  int get todayCount => todayMeals.length;

  double get todayCarbs =>
      todayMeals.fold(0, (sum, meal) => sum + meal.carbs);

  double get todayBolus =>
      todayMeals.fold(0, (sum, meal) => sum + meal.bolus);

  double get todayProtein =>
      todayMeals.fold(0, (sum, meal) => sum + meal.protein);

  Future<void> addMeal(Meal meal) async {
    _meals.add(meal);
    if (_meals.length > _cap) {
      _meals.removeRange(0, _meals.length - _cap);
    }
    notifyListeners();
    await _store.saveMeals(_meals);
  }

  Future<void> removeMeal(Meal meal) async {
    _meals.remove(meal);
    notifyListeners();
    await _store.saveMeals(_meals);
  }
}
