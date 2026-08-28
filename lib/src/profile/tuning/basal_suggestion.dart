import 'package:insulink/src/profile/basal/basal_profile.dart';
import 'package:insulink/src/profile/tuning/clean_hour.dart';

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

  /// How many clean hours went into it. Shown, because a suggestion from three
  /// nights is a different thing from one built on twelve.
  final int samples;

  /// The typical glucose drift across this hour, in mg/dL.
  final double medianDrift;

  double get change => suggested - current;

  bool get isChange => change.abs() >= BasalProfile.step / 2;
}

/// Suggests a basal profile from hours where nothing but basal could have moved
/// the glucose.
///
/// The arithmetic is deliberately the plainest thing that could work: if glucose
/// drifted up by D mg/dL over a clean hour, the insulin missing for that hour is
/// D divided by the correction factor, so the rate for that hour wants to be
/// that much higher. Anything more elaborate would be modelling data this
/// refuses to collect.
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
    required this.currentRates,
  });

  /// The user's correction factor. It converts a glucose drift into the insulin
  /// that would have prevented it.
  final int correctionFactor;

  /// The 24 rates currently programmed, one per hour.
  final List<double> currentRates;

  /// Clean hours needed before an hour of the day is worth a word.
  static const int minSamples = 3;

  /// The most a single proposal may move a rate. A week of nights is thin
  /// evidence, and the cost of being wrong is asymmetric.
  static const double maxChangeFraction = 0.2;

  /// Applied when the current rate is so small that a fraction of it is nothing.
  static const double minChangeRoom = 0.1;

  /// One entry per hour that had enough clean data, in hour order. Hours without
  /// it are absent rather than unchanged: silence is the honest answer.
  List<HourSuggestion> from(List<CleanHour> hours) {
    final byHour = <int, List<int>>{};
    for (final hour in hours) {
      byHour.putIfAbsent(hour.hourOfDay, () => <int>[]).add(hour.drift);
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

  HourSuggestion _forHour(int hour, List<int> drifts) {
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

  /// The middle value, so one unusual night does not carry an hour.
  double _median(List<int> values) {
    final sorted = List<int>.of(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle].toDouble();
    }
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
