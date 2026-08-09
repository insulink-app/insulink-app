import 'cardio_models.dart';

/// Maps a detected GPS segment to a [CardioType], cross-checking the recognised
/// activity against speed. The OS activity recognition routinely mislabels a
/// train/tram/bus as `walking` (low vibration, its own low-power sensors), so
/// speed — the ground truth for what is *impossible on foot* — always wins when
/// the two disagree: a segment faster than any human-powered mode is discarded
/// as a vehicle, and an on-foot label over a too-fast segment is upgraded to the
/// speed-based type (a "walk" at 20 km/h is a vehicle, not a walk). Pure and
/// plugin-free so it stays unit-testable.
///
/// It emits only [CardioType.walk] and [CardioType.bike] — never a jog, which is
/// reserved for a manually started training (see [_bySpeed]).
class CardioActivityClassifier {
  const CardioActivityClassifier();

  /// No human-powered mode sustains an average above this (km/h) over a whole
  /// segment — above it the segment is a vehicle and discarded, whatever the
  /// activity recognition claims. A brisk downhill amateur cyclist stays well
  /// under it; a train/car easily clears it.
  static const _humanPoweredMaxKmh = 30.0;

  /// The training type for a segment, or null to DISCARD it (a vehicle — either
  /// recognised as one, or too fast to be human-powered).
  CardioType? classify({
    required int startMs,
    required int endMs,
    required double avgKmh,
    required List<ActivitySample> activityLog,
  }) {
    final dominant = _dominant(startMs, endMs, activityLog);
    if (dominant == ActivityKind.vehicle || avgKmh > _humanPoweredMaxKmh) {
      return null;
    }
    final bySpeed = _bySpeed(avgKmh);
    final byActivity = _onFootType(dominant);
    if (byActivity == null) {
      return bySpeed;
    }
    // The activity label may up-call speed (a slow uphill ride it knows is a
    // bike) but never DOWN-call it: a "walk"/"run" tag over a bike-speed segment
    // is a misread, so the faster of the two wins.
    return byActivity.index >= bySpeed.index ? byActivity : bySpeed;
  }

  /// The on-foot/bike [CardioType] for an activity kind, or null when the kind
  /// gives no usable signal (still/unknown/none) so speed decides. Vehicle is
  /// handled earlier (discard) and never reaches here.
  ///
  /// A recognised RUN maps to [CardioType.walk], not [CardioType.jog] — see
  /// [_bySpeed] for why auto-detection never emits a jog.
  CardioType? _onFootType(ActivityKind? kind) => switch (kind) {
    ActivityKind.bike => CardioType.bike,
    ActivityKind.run || ActivityKind.walk => CardioType.walk,
    _ => null,
  };

  /// Auto-detection only ever emits walk or bike: [CardioType.jog] stays in the
  /// enum for a MANUALLY started training, but a GPS track can't tell a jog from
  /// a brisk walk or a slow ride reliably enough to label it unasked, and a wrong
  /// label is worse than a coarse one (the user confirms the training either
  /// way). So everything below the bike threshold is a walk.
  CardioType _bySpeed(double avgKmh) {
    return avgKmh > 15 ? CardioType.bike : CardioType.walk;
  }

  /// The activity kind that covered the most of the `[startMs, endMs]` window.
  /// The log holds one entry per change, so each entry's kind persists until the
  /// next; we sum each such interval's overlap with the window. Null when no
  /// activity data overlaps.
  ActivityKind? _dominant(int startMs, int endMs, List<ActivitySample> log) {
    final durations = <ActivityKind, int>{};
    for (var index = 0; index < log.length; index++) {
      final from = log[index].tMs;
      final until = index + 1 < log.length ? log[index + 1].tMs : endMs;
      final overlap = _overlapMs(startMs, endMs, from, until);
      if (overlap > 0) {
        durations.update(
          log[index].kind,
          (value) => value + overlap,
          ifAbsent: () => overlap,
        );
      }
    }
    if (durations.isEmpty) {
      return null;
    }
    return durations.entries
        .reduce((best, entry) => entry.value > best.value ? entry : best)
        .key;
  }

  int _overlapMs(int aStart, int aEnd, int bStart, int bEnd) {
    final start = aStart > bStart ? aStart : bStart;
    final end = aEnd < bEnd ? aEnd : bEnd;
    return end > start ? end - start : 0;
  }
}
