import 'package:insulink/src/nutrition/meal/meal.dart';

/// Carbohydrate from logged meals that has not reached the blood yet — "carbs on
/// board" (COB), the mirror of [ActiveInsulin].
///
/// The bolus calculator needs it while glucose is under target: carbs eaten a
/// few minutes ago to treat that very low are still on their way up, so a second
/// meal must not be charged the full negative correction again.
///
/// ponytail: linear absorption over a fixed [absorption], no per-meal speed and
/// no setting. Shorter than the insulin duration on purpose, so an estimate that
/// is off errs toward FEWER pending carbs, which only ever lowers a dose. Upgrade
/// path if it proves too coarse: a per-meal absorption speed on [Meal].
class CarbsOnBoard {
  const CarbsOnBoard();

  /// How long a logged meal is assumed to take to be absorbed.
  static const Duration absorption = Duration(hours: 2);

  /// Grams across [meals] still to be absorbed at [now] (defaults to the
  /// current time).
  double grams(List<Meal> meals, {DateTime? now}) {
    final at = now ?? DateTime.now();
    return meals.fold(0, (sum, meal) => sum + _remaining(meal, at));
  }

  double _remaining(Meal meal, DateTime at) {
    final elapsed = at.difference(meal.time).inSeconds;
    final fraction = 1 - elapsed / absorption.inSeconds;
    return meal.carbs * fraction.clamp(0.0, 1.0);
  }
}
