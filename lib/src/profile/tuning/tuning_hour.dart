import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/profile/tuning/tuning_model.dart';

/// One wall-clock hour, with everything known about what moved glucose in it.
///
/// It used to be a "clean hour": an hour with no food, no bolus and no
/// automation anywhere near it, and every other hour was thrown away. That is
/// the safest thing to do and it leaves most people with three quiet nights a
/// month to learn from. So an hour now carries what else was acting in it
/// instead of being dropped for it, and the suggestion subtracts that before
/// attributing the rest.
class TuningHour {
  const TuningHour({
    required this.start,
    required this.fromMgdl,
    required this.toMgdl,
    required this.carbsAbsorbed,
    required this.insulinActing,
  });

  final DateTime start;
  final int fromMgdl;
  final int toMgdl;

  /// Grams absorbed during the hour, from every meal reaching into it.
  final double carbsAbsorbed;

  /// Units of bolus and automation insulin that acted during the hour. The
  /// scheduled basal is not in here: it is the thing being tuned.
  final double insulinActing;

  /// Which hour of the day this was, so hours can be pooled across days.
  int get hourOfDay => start.hour;

  /// How far glucose moved, in mg/dL, before anything is explained away.
  int get drift => toMgdl - fromMgdl;
}

/// Collects the hours that can be learned from.
///
/// The rules that remain are about data being ABSENT or unusable, not about the
/// hour being quiet: a missing reading, a glucose the body itself is reacting
/// to, or a stretch older than the automation record can answer for.
class TuningHourFinder {
  const TuningHourFinder({required this.model});

  /// What was acting in each hour. See [TuningModel] for what it assumes.
  final TuningModel model;

  /// The lowest and highest glucose worth learning from. Outside this range the
  /// body's own counter-regulation is doing something no setting can explain.
  static const int minPlausibleMgdl = 70;
  static const int maxPlausibleMgdl = 250;

  /// The hours between [from] and [to] that have readings at both ends.
  ///
  /// [glucoseAt] returns a reading for a moment, or null when there is none: an
  /// hour without readings at both ends is dropped rather than interpolated.
  ///
  /// Hours from before the automation record began are NOT dropped. They used to
  /// be, on the reasoning that an unanswerable "was the automation running?"
  /// reads as "no insulin". But the record starts the first time the automation
  /// is ever switched on (`PodLoopJournal.saveLoopMode`), so before that moment
  /// nothing could have been running and there is nothing to clear. Dropping
  /// them clipped every window to the age of the automation and was why a
  /// longer period changed nothing: somebody who turned the loop on last week
  /// got last week however many months they asked for.
  ///
  /// What that leaves is an old install whose record began late, where an hour
  /// the automation drove reads as having less insulin than it did. The result
  /// then leans toward LESS insulin, which is the safe direction and the same
  /// one the record's own pruning errs in.
  List<TuningHour> find({
    required DateTime from,
    required DateTime to,
    required List<Meal> meals,
    required int? Function(DateTime moment) glucoseAt,
    required double Function(DateTime hour) automationExcessAt,
  }) {
    final hours = <TuningHour>[];
    var start = DateTime(from.year, from.month, from.day, from.hour);
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

  TuningHour? _hourAt(
    DateTime start,
    DateTime end,
    List<Meal> meals,
    int? Function(DateTime moment) glucoseAt,
    double Function(DateTime hour) automationExcessAt,
  ) {
    final fromMgdl = glucoseAt(start);
    final toMgdl = glucoseAt(end);
    if (fromMgdl == null || toMgdl == null) {
      return null;
    }
    if (!_isPlausible(fromMgdl) || !_isPlausible(toMgdl)) {
      return null;
    }
    return TuningHour(
      start: start,
      fromMgdl: fromMgdl,
      toMgdl: toMgdl,
      carbsAbsorbed: model.carbsAbsorbed(meals: meals, from: start, to: end),
      insulinActing: model.insulinActing(
        meals: meals,
        from: start,
        to: end,
        automationExcessAt: automationExcessAt,
      ),
    );
  }

  bool _isPlausible(int mgdl) =>
      mgdl >= minPlausibleMgdl && mgdl <= maxPlausibleMgdl;
}
