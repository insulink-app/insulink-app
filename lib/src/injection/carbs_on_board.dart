import 'dart:math';

import 'package:insulink/src/injection/active_insulin.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/pump/split_bolus.dart';

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

  /// The insulin the unabsorbed carbs of [meals] still call for at
  /// [carbFactor] grams per unit — what the loop must not read as correction.
  ///
  /// Each meal is capped at what is left of its OWN bolus under [insulin], so
  /// carbs eaten with less bolus than they call for (a snack treating a low)
  /// can never cancel insulin they were not dosed with, such as what the loop
  /// added itself. Carbs gone after [absorption] while the bolus still acts
  /// leave that rest counted as correction, the side that asks for less.
  ///
  /// A split bolus counts as the meal's own: the parts logged for it since
  /// ([Meal.splitOf]) and the rest [split] still plans. Without that, a meal
  /// bolused mostly later would read as a big correction, and the loop would
  /// withhold basal while its carbs come in.
  double coverUnits(
    List<Meal> meals, {
    required int carbFactor,
    required ActiveInsulin insulin,
    SplitBolusPlan? split,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    return meals.fold(0, (sum, meal) {
      final carbUnits = _remaining(meal, at) / carbFactor;
      return sum + min(carbUnits, _dosedFor(meal, meals, insulin, split, at));
    });
  }

  /// The insulin still acting that was dosed for [meal]: its own bolus, its
  /// split-bolus parts, and the planned rest when the running plan is its.
  double _dosedFor(
    Meal meal,
    List<Meal> meals,
    ActiveInsulin insulin,
    SplitBolusPlan? split,
    DateTime at,
  ) {
    final parts = meals.where((other) => other.splitOf == meal.logKey);
    final planned = split?.mealKey == meal.logKey
        ? split!.remainingUnitsAt(at)
        : 0.0;
    return insulin.units([meal, ...parts], now: at) + planned;
  }

  double _remaining(Meal meal, DateTime at) {
    final elapsed = at.difference(meal.time).inSeconds;
    final fraction = 1 - elapsed / absorption.inSeconds;
    return meal.carbs * fraction.clamp(0.0, 1.0);
  }
}
