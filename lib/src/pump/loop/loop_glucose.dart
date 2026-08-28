import 'dart:collection';

/// Why sensor data cannot be dosed on. Each case is a separate thing to tell the
/// user, because each one has a different remedy.
enum LoopGlucoseProblem {
  noReadings,
  stale,
  fromTheFuture,
  implausibleValue,
  notEnoughHistory,
  implausibleTrend,
}

/// The glucose input a dosing decision is allowed to be made on.
///
/// Nothing else in the loop reads the glucose archive. A decision is only ever
/// computed from an instance of this, and a usable instance can only exist when
/// the data behind it passed every check below. That is the trust boundary: the
/// arithmetic downstream has no way to tell a bad number from a real one, so a
/// sensor that has gone quiet, jumped, or reported something physiologically
/// impossible must never reach it.
///
/// The trend is measured HERE, by regression over the recent archive, rather
/// than taken from the sensor's own trend field. Two reasons: the G7 and the
/// Libre encode that field differently, and a trend computed from the same
/// points as the value cannot disagree with it. A sensor-reported trend can.
class LoopGlucose {
  const LoopGlucose._({
    required this.mgdl,
    required this.at,
    required this.trendPerMinute,
    required this.problem,
  });

  /// Reads the newest usable input out of [archive], keyed by epoch minute as
  /// `CgmStore.archiveRange` returns it.
  ///
  /// Returns an instance carrying a [problem] rather than throwing or returning
  /// null, so the caller has something to write into the audit log either way. A
  /// cycle that dosed nothing still has to say why.
  factory LoopGlucose.from(
    SplayTreeMap<int, int> archive, {
    required DateTime now,
  }) {
    if (archive.isEmpty) {
      return _unusable(LoopGlucoseProblem.noReadings);
    }
    final newestMinute = archive.lastKey()!;
    final at = DateTime.fromMillisecondsSinceEpoch(
      newestMinute * Duration.millisecondsPerMinute,
    );
    final mgdl = archive[newestMinute]!;
    if (at.isAfter(now.add(clockTolerance))) {
      return _unusable(LoopGlucoseProblem.fromTheFuture);
    }
    if (now.difference(at) > maxAge) {
      return _unusable(LoopGlucoseProblem.stale);
    }
    if (mgdl < minPlausibleMgdl || mgdl > maxPlausibleMgdl) {
      return _unusable(LoopGlucoseProblem.implausibleValue);
    }
    final recent = _pointsWithin(archive, newestMinute);
    if (recent.length < minPointsForTrend) {
      return _unusable(LoopGlucoseProblem.notEnoughHistory);
    }
    final trend = _slopePerMinute(recent);
    if (trend.abs() > maxPlausibleTrendPerMinute) {
      return _unusable(LoopGlucoseProblem.implausibleTrend);
    }
    return LoopGlucose._(
      mgdl: mgdl,
      at: at,
      trendPerMinute: trend,
      problem: null,
    );
  }

  /// How old the newest reading may be. A G7 delivers every five minutes and a
  /// Libre every minute, so anything past this means the link is down, not that
  /// the sensor is between readings.
  static const Duration maxAge = Duration(minutes: 12);

  /// Slack for a reading stamped slightly ahead of the phone's clock. Beyond it
  /// the two clocks disagree enough that no age can be trusted.
  static const Duration clockTolerance = Duration(minutes: 2);

  /// The window the trend is measured over.
  static const Duration trendWindow = Duration(minutes: 20);

  static const int minPointsForTrend = 3;
  static const int minPlausibleMgdl = 30;
  static const int maxPlausibleMgdl = 500;

  /// 8 mg/dL per minute is 40 mg/dL in five minutes. Real glucose does not move
  /// that fast; a sensor artefact does.
  static const double maxPlausibleTrendPerMinute = 8.0;

  /// The newest reading, in mg/dL. Meaningless unless [isUsable].
  final int mgdl;

  final DateTime at;

  /// Measured change in mg/dL per minute, negative when falling.
  final double trendPerMinute;

  final LoopGlucoseProblem? problem;

  bool get isUsable => problem == null;

  /// Where the trend alone puts glucose in [minutes], with no insulin action
  /// accounted for.
  double projected(int minutes) => mgdl + trendPerMinute * minutes;

  static LoopGlucose _unusable(LoopGlucoseProblem problem) => LoopGlucose._(
        mgdl: 0,
        at: DateTime.fromMillisecondsSinceEpoch(0),
        trendPerMinute: 0,
        problem: problem,
      );

  /// The readings inside [trendWindow] of the newest one, as (minute, mg/dL).
  ///
  /// Measured back from the newest READING rather than from now, so a cycle that
  /// runs a few minutes after a reading arrived still sees the full window.
  static List<({int minute, int mgdl})> _pointsWithin(
    SplayTreeMap<int, int> archive,
    int newestMinute,
  ) {
    final earliest = newestMinute - trendWindow.inMinutes;
    return [
      for (final entry in archive.entries)
        if (entry.key >= earliest &&
            entry.value >= minPlausibleMgdl &&
            entry.value <= maxPlausibleMgdl)
          (minute: entry.key, mgdl: entry.value),
    ];
  }

  /// Slope in mg/dL per minute, as the median of every pair of points.
  ///
  /// Theil-Sen rather than least squares, which was tried first and is not good
  /// enough here. Least squares gives an outlier the most leverage exactly where
  /// a sensor most often produces one, at the edge of the window: a single point
  /// 40 mg/dL out of line bends a genuine -1.0 into -2.6, near the -3.0 that
  /// reading only the two endpoints would give. The median of the pairwise
  /// slopes returns -1.0 on that same data, because the pairs among the four
  /// good points outvote every pair touching the bad one.
  ///
  /// That matters because this number drives the hypo prediction. A trend read
  /// too steep suspends a loop that had no reason to stop, and a trend read too
  /// flat is worse.
  ///
  /// Quadratic in the number of points, which is at most 20 here.
  static double _slopePerMinute(List<({int minute, int mgdl})> points) {
    final slopes = <double>[];
    for (var first = 0; first < points.length; first++) {
      for (var second = first + 1; second < points.length; second++) {
        final minutes = points[second].minute - points[first].minute;
        if (minutes != 0) {
          slopes.add((points[second].mgdl - points[first].mgdl) / minutes);
        }
      }
    }
    if (slopes.isEmpty) {
      return 0;
    }
    slopes.sort();
    final middle = slopes.length ~/ 2;
    if (slopes.length.isOdd) {
      return slopes[middle];
    }
    return (slopes[middle - 1] + slopes[middle]) / 2;
  }
}
