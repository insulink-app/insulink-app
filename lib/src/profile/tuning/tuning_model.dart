import 'package:insulink/src/nutrition/meal/meal.dart';

/// What is KNOWN to have been acting over a stretch of time.
///
/// This is what lets the tuning use ordinary days instead of only quiet nights.
/// The earlier version threw away every hour that had food or a bolus near it,
/// which is honest but leaves most people with almost nothing to learn from. So
/// the known causes are now measured and subtracted, and only what neither food
/// nor insulin explains is attributed to the setting being tuned.
///
/// **It is a model, and a plain one.** Insulin acts evenly over the configured
/// duration and carbohydrates absorb evenly over [carbAbsorption], the same
/// linear assumption `ActiveInsulin` already makes for the insulin-on-board
/// readout. Real absorption peaks and tails; the timing error that leaves is why
/// every result is taken as a median across days and capped before it is
/// offered.
///
/// ponytail: linear, shared by carbohydrates and insulin through one overlap
/// helper. Ceiling: it misplaces effect WITHIN a window, so a single window is
/// worth little and only the median of many says anything. Upgrade path if that
/// proves too coarse: the exponential insulin curve and a carbohydrate model
/// with a delay, both of which need a peak-time setting the app does not have.
class TuningModel {
  const TuningModel({
    required this.insulinDuration,
    this.carbAbsorption = const Duration(hours: 4),
  });

  /// How long a dose keeps acting, from the bolus settings.
  final Duration insulinDuration;

  /// How long food keeps being absorbed. Longer than most meals, because the
  /// slow ones are the case that otherwise looks like a wrong setting.
  final Duration carbAbsorption;

  /// Units of insulin that acted between [from] and [to]: the logged boluses,
  /// plus what the automation delivered above the user's schedule.
  ///
  /// The scheduled basal is deliberately absent, for the reason [InsulinOnBoard]
  /// gives: it is maintenance insulin the body is in equilibrium with. Only the
  /// deviation from it is extra insulin acting.
  double insulinActing({
    required List<Meal> meals,
    required DateTime from,
    required DateTime to,
    required double Function(DateTime hour) automationExcessAt,
  }) {
    var units = 0.0;
    for (final meal in meals) {
      if (meal.bolus > 0) {
        units += meal.bolus * _share(meal.time, insulinDuration, from, to);
      }
    }
    var hour = _hourOf(from.subtract(insulinDuration));
    while (hour.isBefore(to)) {
      final excess = automationExcessAt(hour);
      if (excess > 0) {
        units += excess * _share(hour, insulinDuration, from, to);
      }
      hour = hour.add(const Duration(hours: 1));
    }
    return units;
  }

  /// Grams of carbohydrate absorbed between [from] and [to], from every logged
  /// meal whose absorption reaches into the window.
  double carbsAbsorbed({
    required List<Meal> meals,
    required DateTime from,
    required DateTime to,
  }) {
    var grams = 0.0;
    for (final meal in meals) {
      if (meal.carbs > 0) {
        grams += meal.carbs * _share(meal.time, carbAbsorption, from, to);
      }
    }
    return grams;
  }

  /// How much of something that started at [start] and lasts [span] falls inside
  /// [from] to [to]. The one piece of arithmetic behind both sums.
  double _share(DateTime start, Duration span, DateTime from, DateTime to) {
    final end = start.add(span);
    final overlapStart = start.isAfter(from) ? start : from;
    final overlapEnd = end.isBefore(to) ? end : to;
    final minutes = overlapEnd.difference(overlapStart).inMinutes;
    return minutes <= 0 ? 0 : minutes / span.inMinutes;
  }

  DateTime _hourOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day, moment.hour);
}
