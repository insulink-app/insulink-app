import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/profile/tuning/tuning_hour.dart';
import 'package:insulink/src/profile/tuning/tuning_model.dart';

/// One stretch of time after a dose, with everything known about what acted in
/// it.
///
/// The dose counterpart of [TuningHour], and it works the same way: a
/// neighbouring meal or a second bolus no longer disqualifies the window. What
/// they contributed is measured by [TuningModel] and carried here, so the
/// arithmetic can take it into account instead of the window being thrown away.
class TuningDose {
  const TuningDose({
    required this.at,
    required this.carbsAbsorbed,
    required this.insulinActing,
    required this.startMgdl,
    required this.endMgdl,
    required this.minutesToEnd,
    required this.isCorrection,
    this.minutesToLowest,
  });

  final DateTime at;

  /// Grams absorbed across the window, from every meal reaching into it.
  final double carbsAbsorbed;

  /// Units that acted across the window: this dose, anything still working from
  /// before it, and what the automation added.
  final double insulinActing;

  /// Glucose when the dose was given.
  final int startMgdl;

  /// Glucose at the end of the window: where it settled after a meal, the LOWEST
  /// point reached after a correction.
  final int endMgdl;

  /// How long the window was.
  final int minutesToEnd;

  /// How long the dose took to reach its lowest point, or null when that could
  /// not be read: no quiet stretch after it, or glucose still falling when the
  /// stretch ran out.
  ///
  /// The measured length of the insulin's action, and it is deliberately taken
  /// from MEAL doses as well. Waiting for a correction dose leaves anybody who
  /// always boluses with food without an answer for the insulin duration, and
  /// the end of a meal's fall is the same event: the food is long absorbed, so
  /// the point where glucose stops falling is where the insulin stopped working.
  final int? minutesToLowest;

  /// Whether this was insulin against a high with no food of its own. Only such
  /// a window says anything about the correction factor or the insulin duration.
  final bool isCorrection;

  /// How far glucose moved over the window, in mg/dL.
  int get drift => endMgdl - startMgdl;
}

/// Collects the windows that can be learned from.
///
/// The rules that remain are about data being absent or unusable, plus the one
/// physiological refusal: a correction that ended in a hypoglycaemia.
class TuningDoseFinder {
  const TuningDoseFinder({
    required this.model,
    this.mealSettle = const Duration(hours: 5),
    this.correctionWindow = const Duration(hours: 8),
  });

  /// What was acting across each window.
  final TuningModel model;

  /// How long a meal is given to finish. Long enough to cover a slow one.
  final Duration mealSettle;

  /// The longest a correction is watched for its lowest point. The top of what
  /// anybody sets as an insulin duration, so the measurement is not capped by
  /// the setting it is meant to inform.
  final Duration correctionWindow;

  /// A correction dose below this says more about rounding than about insulin.
  static const double minCorrectionBolus = 0.5;

  /// Insulin given at a normal glucose is not a correction, whatever it was
  /// logged as, and its fall would be attributed to the wrong thing.
  static const int minCorrectionStartMgdl = 140;

  /// A correction window ends at the next logged food, because carbohydrates
  /// hide the fall this is measuring. Shorter than this and there is not enough
  /// fall to read.
  static const Duration minCorrectionWindow = Duration(hours: 2);

  /// How much of the window must actually have readings. One with a hole in it
  /// can hide the true lowest point.
  static const double minCoverage = 0.8;

  /// The dose windows between [from] and [to]. See [TuningHourFinder] for what
  /// [glucoseAt] and [automationExcessAt] mean, and for why a window from before
  /// the automation record began is kept rather than dropped.
  List<TuningDose> find({
    required DateTime from,
    required DateTime to,
    required List<Meal> meals,
    required int? Function(DateTime moment) glucoseAt,
    required double Function(DateTime hour) automationExcessAt,
  }) {
    final doses = <TuningDose>[];
    for (final meal in meals) {
      if (meal.bolus <= 0 ||
          meal.time.isBefore(from) ||
          meal.time.isAfter(to)) {
        continue;
      }
      final dose = _doseFor(meal, meals, glucoseAt, automationExcessAt);
      if (dose != null) {
        doses.add(dose);
      }
    }
    return doses;
  }

  TuningDose? _doseFor(
    Meal meal,
    List<Meal> meals,
    int? Function(DateTime moment) glucoseAt,
    double Function(DateTime hour) automationExcessAt,
  ) {
    final start = glucoseAt(meal.time);
    if (start == null || !_isPlausible(start)) {
      return null;
    }
    final isCorrection = meal.carbs <= 0;
    final lowest = _lowestAfterPeak(meal, meals, glucoseAt);
    if (isCorrection &&
        (lowest == null ||
            start < minCorrectionStartMgdl ||
            meal.bolus < minCorrectionBolus)) {
      return null;
    }
    final end = isCorrection ? lowest : _mealEnd(meal, glucoseAt);
    if (end == null) {
      return null;
    }
    final until = meal.time.add(Duration(minutes: end.minutes));
    return TuningDose(
      at: meal.time,
      carbsAbsorbed: model.carbsAbsorbed(
        meals: meals,
        from: meal.time,
        to: until,
      ),
      insulinActing: model.insulinActing(
        meals: meals,
        from: meal.time,
        to: until,
        automationExcessAt: automationExcessAt,
      ),
      startMgdl: start,
      endMgdl: end.mgdl,
      minutesToEnd: end.minutes,
      isCorrection: isCorrection,
      minutesToLowest: lowest?.minutes,
    );
  }

  /// Where glucose settled once the meal had finished.
  ({int minutes, int mgdl})? _mealEnd(
    Meal meal,
    int? Function(DateTime moment) glucoseAt,
  ) {
    final settled = glucoseAt(meal.time.add(mealSettle));
    if (settled == null || !_isPlausible(settled)) {
      return null;
    }
    return (minutes: mealSettle.inMinutes, mgdl: settled);
  }

  /// The lowest point glucose reached after the dose, and how long it took.
  ///
  /// The window stops at the next logged carbohydrates, because food ends the
  /// stretch this is reading. Measured from the PEAK, so a meal's own rise is
  /// not mistaken for the start of the fall; for a correction the peak is the
  /// dose itself and this is simply the fall.
  ///
  /// The lowest point has to fall strictly INSIDE the window: one that lands on
  /// its edge means glucose was still going down when the window ran out, so the
  /// drop measured so far understates the dose, which is the one direction a
  /// wrong correction factor must not go.
  ///
  /// A fall that ended in a hypoglycaemia is dropped for the mirror reason: the
  /// body stops it itself down there, so the measured drop is again smaller than
  /// the insulin caused.
  ({int minutes, int mgdl})? _lowestAfterPeak(
    Meal meal,
    List<Meal> meals,
    int? Function(DateTime moment) glucoseAt,
  ) {
    final window = _windowBefore(_nextFood(meal, meals));
    if (window == null) {
      return null;
    }
    final samples = _sample(meal.time, window, glucoseAt);
    if (samples.length < window.inMinutes / _sampleMinutes * minCoverage) {
      return null;
    }
    var peak = samples.first;
    for (final sample in samples) {
      if (sample.mgdl > peak.mgdl) {
        peak = sample;
      }
    }
    final after = samples.where((sample) => sample.minutes > peak.minutes);
    if (after.isEmpty) {
      return null;
    }
    // The FIRST time the lowest value is reached, so a flat tail at that value
    // is read as the fall having ended there rather than at the window's edge.
    var lowest = after.first;
    for (final sample in after) {
      if (sample.mgdl < lowest.mgdl) {
        lowest = sample;
      }
    }
    if (lowest.minutes >= samples.last.minutes || !_isPlausible(lowest.mgdl)) {
      return null;
    }
    return lowest;
  }

  /// The window to watch, cut short by [nextFood] and refused when that leaves
  /// too little of it.
  Duration? _windowBefore(Duration? nextFood) {
    if (nextFood == null) {
      return correctionWindow;
    }
    return nextFood < minCorrectionWindow ? null : nextFood;
  }

  /// How long after [meal] the next carbohydrates were logged, or null if none
  /// were inside [correctionWindow].
  Duration? _nextFood(Meal meal, List<Meal> meals) {
    Duration? soonest;
    for (final other in meals) {
      if (other.carbs <= 0 || !other.time.isAfter(meal.time)) {
        continue;
      }
      final after = other.time.difference(meal.time);
      if (after <= correctionWindow && (soonest == null || after < soonest)) {
        soonest = after;
      }
    }
    return soonest;
  }

  static const int _sampleMinutes = 5;

  /// The readings across a window, at the CGM's own cadence.
  List<({int minutes, int mgdl})> _sample(
    DateTime from,
    Duration window,
    int? Function(DateTime moment) glucoseAt,
  ) {
    final samples = <({int minutes, int mgdl})>[];
    for (
      var minutes = 0;
      minutes <= window.inMinutes;
      minutes += _sampleMinutes
    ) {
      final mgdl = glucoseAt(from.add(Duration(minutes: minutes)));
      if (mgdl != null) {
        samples.add((minutes: minutes, mgdl: mgdl));
      }
    }
    return samples;
  }

  bool _isPlausible(int mgdl) =>
      mgdl >= TuningHourFinder.minPlausibleMgdl &&
      mgdl <= TuningHourFinder.maxPlausibleMgdl;
}
