/// How full the pod's reservoir is, as far as the pod can say.
///
/// A model rather than a lump of logic in the widget, mirroring [DeviceLifespan]
/// next to it: the awkward part is not the drawing, it is that the pod answers
/// "I cannot measure that much" and "I have not been asked yet" with the same
/// missing number, and those are opposite answers.
class PodReservoirLevel {
  const PodReservoirLevel({required this.hasStatus, required this.units});

  /// Whether a status has been read at all. Without one there is no reading to
  /// show, which is NOT the same as a reading of zero.
  final bool hasStatus;

  /// Units the pod reported, or null when it reported more than it can measure.
  final double? units;

  /// Units at or below which the reservoir is worth calling out.
  static const double lowUnits = 10.0;

  /// The top of the scale. Deliberately the pod's MEASURING range, not its 200 U
  /// capacity: a bar that ran to 200 would sit near empty for a pod that is
  /// perfectly full, because the pod never reports the upper range at all.
  static const double measurableUnits = 50.0;

  /// How much of the track is filled. An unread pod shows an empty track rather
  /// than a guess, and the unmeasurable upper range shows a full one.
  double get fraction {
    if (!hasStatus) {
      return 0;
    }
    final reported = units;
    if (reported == null) {
      return 1;
    }
    return (reported / measurableUnits).clamp(0.0, 1.0);
  }

  /// Whether the reading is low enough to warn about. Only ever true for a number
  /// the pod actually gave: "more than I can measure" is the opposite of low.
  bool get isLow {
    final reported = units;
    return reported != null && reported <= lowUnits;
  }

  /// Whether the pod gave a figure that can be printed.
  bool get hasNumber => hasStatus && units != null;

  /// Whether the pod said it holds more than it can measure.
  bool get isAboveRange => hasStatus && units == null;
}
