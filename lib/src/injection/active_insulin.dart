import 'package:insulink/src/nutrition/meal/meal.dart';

/// Insulin still working from recent boluses — "active insulin" / insulin on
/// board (IOB). Every logged [Meal] carries the bolus it was dosed with, so the
/// meal log is the dose history; no separate store is needed.
///
/// A dose decays linearly over [duration] (the user's configured insulin
/// activity time, 3 h by default): the fraction still active falls evenly from
/// 1 at injection to 0 once the duration has passed. Doses older than that
/// contribute nothing.
///
/// ponytail: linear decay, not a Walsh/exponential curve. Linear needs only the
/// duration the user configures, while a curve needs a peak-activity time as a
/// second setting. Ceiling: it overstates IOB early and understates it late (a
/// real bolus peaks after ~75 min). Upgrade path if the flat profile proves too
/// coarse: add a peak-time setting and swap [_remaining] for the exponential
/// model Loop/AndroidAPS use.
class ActiveInsulin {
  const ActiveInsulin(this.duration);

  /// How long a bolus keeps acting (`ProfileBolusState.insulinDuration`).
  final Duration duration;

  /// Units still active across [meals] at [now] (defaults to the current time).
  double units(List<Meal> meals, {DateTime? now}) {
    final at = now ?? DateTime.now();
    return meals.fold(0, (sum, meal) => sum + _remaining(meal, at));
  }

  /// When the newest still-active dose wears off, or null while nothing is
  /// active — the "active until" the overview shows next to the units.
  DateTime? activeUntil(List<Meal> meals, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final ends = [
      for (final meal in meals)
        if (_remaining(meal, at) > 0) meal.time.add(duration),
    ];
    if (ends.isEmpty) {
      return null;
    }
    return ends.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Each dose still contributing IOB with the units of it left, newest first —
  /// what the active-insulin detail page lists. A dose is a logged [Meal]'s
  /// bolus, so tapping one opens that meal.
  List<({Meal meal, double remaining})> activeDoses(
    List<Meal> meals, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final doses = [
      for (final meal in meals)
        if (_remaining(meal, at) > 0)
          (meal: meal, remaining: _remaining(meal, at)),
    ];
    doses.sort((first, second) => second.meal.time.compareTo(first.meal.time));
    return doses;
  }

  /// The IOB curve across [meals]: total active units sampled every [step] from
  /// the earliest still-active dose to when the last wears off. Only doses
  /// already given by each sample time count, so the curve ramps up at each
  /// injection and decays away — what the active-insulin page graphs. Empty when
  /// nothing is active.
  List<({DateTime at, double units})> curve(
    List<Meal> meals, {
    DateTime? now,
    Duration step = const Duration(minutes: 5),
  }) {
    final at = now ?? DateTime.now();
    final active = activeDoses(meals, now: at);
    if (active.isEmpty) {
      return const [];
    }
    final start = active
        .map((dose) => dose.meal.time)
        .reduce((first, second) => first.isBefore(second) ? first : second);
    final end = activeUntil(meals, now: at)!;
    final points = <({DateTime at, double units})>[];
    for (var sample = start; !sample.isAfter(end); sample = sample.add(step)) {
      points.add((at: sample, units: _iobAt(meals, sample)));
    }
    return points;
  }

  /// Total IOB at [sample], counting only doses already given by then — a future
  /// dose contributes nothing, unlike [units] (which is only ever read at "now").
  double _iobAt(List<Meal> meals, DateTime sample) {
    return meals
        .where((meal) => !meal.time.isAfter(sample))
        .fold(0.0, (sum, meal) => sum + _remaining(meal, sample));
  }

  /// The share of [meal]'s bolus still active at [at]. Clamping covers both
  /// ends: a dose past [duration] gives 0, and a clock skew that dates a meal
  /// into the future can never yield more than the dose itself.
  double _remaining(Meal meal, DateTime at) {
    final elapsed = at.difference(meal.time).inSeconds;
    final fraction = 1 - elapsed / duration.inSeconds;
    return meal.bolus * fraction.clamp(0.0, 1.0);
  }
}
