import 'dart:math';

/// Keeps the demo's CURRENT glucose in the target range, so a visitor always
/// opens the app on a green headline, without flattening the month behind it.
///
/// Values are pulled back softly rather than clipped: above [softHigh] a value
/// approaches [softHigh] + [headroom] but never reaches it, and below [softLow]
/// likewise, so a meal rise bends over into a plateau instead of hitting a wall.
/// The history eases into this over [easeIn] before now; older highs and lows
/// stay as generated, so time in range still has something to report.
class DemoGlucoseRange {
  const DemoGlucoseRange();

  static const double softHigh = 165;
  static const double softLow = 92;
  static const double headroom = 12;
  static const Duration easeIn = Duration(hours: 3);

  /// [value] pulled fully into range: at most 177, at least 80 mg/dL.
  double keep(double value) {
    if (value > softHigh) {
      return softHigh + headroom * (1 - exp(-(value - softHigh) / headroom));
    }
    if (value < softLow) {
      return softLow - headroom * (1 - exp(-(softLow - value) / headroom));
    }
    return value;
  }

  /// [value] at [time], pulled into range by how close [time] is to [end]:
  /// untouched before [easeIn], fully kept at [end], smoothly in between.
  double easedTowards(double value, DateTime time, DateTime end) {
    final remaining = end.difference(time).inSeconds / easeIn.inSeconds;
    final share = (1 - remaining).clamp(0.0, 1.0);
    final weight = share * share * (3 - 2 * share);
    return value + weight * (keep(value) - value);
  }
}
