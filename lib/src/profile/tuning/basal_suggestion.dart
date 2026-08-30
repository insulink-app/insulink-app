import 'package:insulink/src/profile/basal/basal_profile.dart';
import 'package:insulink/src/profile/tuning/tuning_hour.dart';

/// What one hour of the day suggests about the basal rate.
class HourSuggestion {
  const HourSuggestion({
    required this.hour,
    required this.current,
    required this.suggested,
    required this.samples,
    required this.medianDrift,
  });

  final int hour;

  /// The rate currently programmed for this hour, in U/h.
  final double current;

  /// What the clean hours suggest instead, already limited and snapped.
  final double suggested;

  /// How many hours went into it. Shown, because a suggestion from three
  /// nights is a different thing from one built on twelve.
  final int samples;

  /// The typical UNEXPLAINED glucose movement across this hour, in mg/dL: what
  /// it did with the effect of food and bolus insulin already taken off.
  final double medianDrift;

  double get change => suggested - current;

  bool get isChange => change.abs() >= BasalProfile.step / 2;
}

/// Suggests a basal profile from what an hour's glucose did that food and bolus
/// insulin do not explain.
///
/// The arithmetic is the plainest thing that could work. Over one hour:
///
/// ```
/// suggested = current + drift / correctionFactor
///                     + insulinActing
///                     - carbsAbsorbed / carbFactor
/// ```
///
/// The first term is the old one: glucose that drifted up by D mg/dL was short
/// of D / correctionFactor units. The other two put back what else was acting,
/// so an hour after a meal can be used instead of thrown away: the insulin that
/// worked in that hour was not basal, and the carbohydrates absorbed in it were
/// not a basal shortfall. On a quiet hour both are zero and this is exactly the
/// arithmetic it always was.
///
/// What that trades away is stated plainly: those two terms come from
/// [TuningModel], which spreads insulin and carbohydrates EVENLY over their
/// durations. Real ones peak. So a single hour after a meal is worth little, and
/// only the median across days, together with the cap below, makes a proposal
/// out of them.
///
/// **Nothing here is ever applied.** It produces a proposal for a person to read,
/// and every guard below exists to keep that proposal from being confidently
/// wrong:
///
///  * an hour needs [minSamples] clean days before it says anything at all;
///  * the MEDIAN drift is used, not the mean, so one bad night cannot carry an
///    hour on its own;
///  * a change is capped at [maxChangeFraction] of the current rate, because a
///    week of data is not enough to justify a large move and a wrong large move
///    is a nocturnal hypoglycaemia;
///  * the result is snapped to the pump's own 0.05 U/h grid and floored at zero.
class BasalSuggestion {
  const BasalSuggestion({
    required this.correctionFactor,
    required this.carbFactor,
    required this.currentRates,
  });

  /// The user's correction factor. It converts a glucose drift into the insulin
  /// that would have prevented it.
  final int correctionFactor;

  /// The user's carbohydrate factor, which turns the grams absorbed in an hour
  /// into the insulin they needed.
  final int carbFactor;

  /// The 24 rates currently programmed, one per hour.
  final List<double> currentRates;

  /// Hours needed before an hour of the day is worth a word.
  static const int minSamples = 3;

  /// The most a single proposal may move a rate. A week of nights is thin
  /// evidence, and the cost of being wrong is asymmetric.
  static const double maxChangeFraction = 0.2;

  /// Applied when the current rate is so small that a fraction of it is nothing.
  static const double minChangeRoom = 0.1;

  /// The most of an hour's movement that may come from the model rather than
  /// from the reading, in mg/dL.
  ///
  /// The last refusal left. An hour in which food and insulin account for more
  /// than this is an hour whose answer is mostly arithmetic about absorption
  /// timing, and that is the part the model is worst at.
  static const double maxModelledMgdl = 100;

  /// One entry per hour of the day with enough data, in hour order. Hours
  /// without it are absent rather than unchanged: silence is the honest answer.
  List<HourSuggestion> from(List<TuningHour> hours) {
    final byHour = <int, List<double>>{};
    for (final hour in hours) {
      final unexplained = _unexplained(hour);
      if (unexplained != null) {
        byHour.putIfAbsent(hour.hourOfDay, () => <double>[]).add(unexplained);
      }
    }
    final suggestions = <HourSuggestion>[];
    for (var hour = 0; hour < 24; hour++) {
      final drifts = byHour[hour];
      if (drifts == null || drifts.length < minSamples) {
        continue;
      }
      suggestions.add(_forHour(hour, drifts));
    }
    return suggestions;
  }

  /// What the hour did that food and insulin do NOT account for, as mg/dL, or
  /// null when the model carried too much of it to be worth reading.
  double? _unexplained(TuningHour hour) {
    final fromInsulin = hour.insulinActing * correctionFactor;
    final fromCarbs = hour.carbsAbsorbed * correctionFactor / carbFactor;
    if (fromInsulin > maxModelledMgdl || fromCarbs > maxModelledMgdl) {
      return null;
    }
    return hour.drift + fromInsulin - fromCarbs;
  }

  HourSuggestion _forHour(int hour, List<double> drifts) {
    final drift = _median(drifts);
    final current = _currentAt(hour);
    final wanted = current + drift / correctionFactor;
    return HourSuggestion(
      hour: hour,
      current: current,
      suggested: _limited(current, wanted),
      samples: drifts.length,
      medianDrift: drift,
    );
  }

  /// The proposal, held to a fraction of the current rate and put on the pump's
  /// grid. Rounded to nearest here, unlike a delivery: this is a number to read
  /// and discuss, not one being sent to a pump.
  double _limited(double current, double wanted) {
    final room = current * maxChangeFraction;
    final allowed = room > minChangeRoom ? room : minChangeRoom;
    final capped = wanted.clamp(current - allowed, current + allowed);
    final snapped =
        (capped / BasalProfile.step).round() * BasalProfile.step;
    return snapped > 0 ? snapped : 0;
  }

  double _currentAt(int hour) {
    if (currentRates.length != 24) {
      return 0;
    }
    final rate = currentRates[hour];
    return rate.isFinite && rate > 0 ? rate : 0;
  }

  /// The middle value, so one unusual day does not carry an hour.
  double _median(List<double> values) {
    final sorted = List<double>.of(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle];
    }
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
