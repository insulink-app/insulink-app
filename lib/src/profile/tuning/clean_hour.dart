import 'package:insulink/src/nutrition/meal/meal.dart';

/// One wall-clock hour in which glucose moved for only ONE explicable reason.
///
/// This is the whole safety idea of the tuning, and it is a refusal rather than
/// a cleverness. Glucose drift has several possible causes at once: too little
/// basal, a wrong carbohydrate ratio, a wrong correction factor, a snack nobody
/// logged. Software that attributes an unexplained rise to basal will raise the
/// basal, and a basal raised because of a forgotten biscuit causes a night-time
/// hypoglycaemia days later.
///
/// So nothing is attributed. An hour counts only when every OTHER cause has been
/// ruled out, and hours that cannot be cleared are dropped. That leaves fewer
/// hours to learn from, and the ones left mean what they appear to mean.
class CleanHour {
  const CleanHour({
    required this.start,
    required this.fromMgdl,
    required this.toMgdl,
  });

  final DateTime start;
  final int fromMgdl;
  final int toMgdl;

  /// Which hour of the day this was, so hours can be pooled across days.
  int get hourOfDay => start.hour;

  /// How far glucose moved, in mg/dL. Positive means it rose, which in a clean
  /// hour means there was too little insulin.
  int get drift => toMgdl - fromMgdl;
}

/// Decides which hours are clean enough to learn from.
///
/// Every rule here removes data. That is the point: the value of the result
/// comes from what was thrown away, not from what was kept.
class CleanHourFinder {
  const CleanHourFinder({
    required this.insulinDuration,
    this.carbShadow = const Duration(hours: 4),
  });

  /// How long a bolus keeps acting. An hour with insulin still working from a
  /// dose cannot be blamed on basal.
  final Duration insulinDuration;

  /// How long a meal keeps being absorbed. Longer than most meals, because
  /// slow-absorbing food is exactly the case that would otherwise be mistaken
  /// for a basal problem.
  final Duration carbShadow;

  /// The lowest and highest glucose worth learning from. Outside this range the
  /// body's own counter-regulation is doing something a basal rate cannot
  /// explain.
  static const int minPlausibleMgdl = 70;
  static const int maxPlausibleMgdl = 250;

  /// The hours in [from] to [to] that nothing but basal can explain.
  ///
  /// [glucoseAt] returns a reading for a moment, or null when there is none:
  /// an hour without readings at both ends is dropped rather than interpolated.
  ///
  /// [automationKnownSince] is how far back [automationExcessAt] can actually
  /// answer. Hours older than it are dropped rather than trusted, because an
  /// unanswerable "was the automation running?" reads as "no" and would let an
  /// hour the automation drove count as evidence about the SCHEDULE. Its glucose
  /// fell because of extra insulin, so the hour would argue for lowering a basal
  /// rate that was never the reason. Null means there is nothing to verify,
  /// which is the case with no pump at all.
  List<CleanHour> find({
    required DateTime from,
    required DateTime to,
    required List<Meal> meals,
    required int? Function(DateTime moment) glucoseAt,
    required double Function(DateTime hour) automationExcessAt,
    DateTime? automationKnownSince,
  }) {
    final hours = <CleanHour>[];
    final earliest = automationKnownSince;
    var start = DateTime(from.year, from.month, from.day, from.hour);
    if (earliest != null && start.isBefore(earliest)) {
      start = DateTime(
        earliest.year,
        earliest.month,
        earliest.day,
        earliest.hour,
      );
    }
    while (start.isBefore(to)) {
      final end = start.add(const Duration(hours: 1));
      final hour = _hourAt(start, end, meals, glucoseAt, automationExcessAt);
      if (hour != null) {
        hours.add(hour);
      }
      start = end;
    }
    return hours;
  }

  CleanHour? _hourAt(
    DateTime start,
    DateTime end,
    List<Meal> meals,
    int? Function(DateTime moment) glucoseAt,
    double Function(DateTime hour) automationExcessAt,
  ) {
    if (_hasFood(start, meals) || _hasInsulin(start, meals)) {
      return null;
    }
    if (automationExcessAt(start) > 0) {
      return null;
    }
    final fromMgdl = glucoseAt(start);
    final toMgdl = glucoseAt(end);
    if (fromMgdl == null || toMgdl == null) {
      return null;
    }
    if (!_isPlausible(fromMgdl) || !_isPlausible(toMgdl)) {
      return null;
    }
    return CleanHour(start: start, fromMgdl: fromMgdl, toMgdl: toMgdl);
  }

  bool _isPlausible(int mgdl) =>
      mgdl >= minPlausibleMgdl && mgdl <= maxPlausibleMgdl;

  /// Carbohydrates eaten within the shadow before this hour, or during it.
  bool _hasFood(DateTime start, List<Meal> meals) {
    final earliest = start.subtract(carbShadow);
    final end = start.add(const Duration(hours: 1));
    return meals.any((meal) =>
        meal.carbs > 0 && meal.time.isAfter(earliest) && meal.time.isBefore(end));
  }

  /// A bolus still working, from before this hour or inside it.
  bool _hasInsulin(DateTime start, List<Meal> meals) {
    final earliest = start.subtract(insulinDuration);
    final end = start.add(const Duration(hours: 1));
    return meals.any((meal) =>
        meal.bolus > 0 && meal.time.isAfter(earliest) && meal.time.isBefore(end));
  }
}
