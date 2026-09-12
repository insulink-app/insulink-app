import 'dart:collection';
import 'dart:math' as math;

import 'package:insulink/src/analysis/forecast/forecast_backtest.dart';

/// One past forecast next to what the sensor actually read at its target time.
class ForecastOutcome {
  const ForecastOutcome({
    required this.at,
    required this.predicted,
    required this.persistence,
    required this.actual,
    this.lo,
    this.hi,
  });

  final DateTime at;
  final int predicted;
  final int persistence;
  final int actual;
  final int? lo;
  final int? hi;

  int get error => predicted - actual;

  bool get isCovered =>
      lo != null && hi != null && actual >= lo! && actual <= hi!;
}

/// How a window of forecasts turned out. All errors are mg/dL.
///
/// [skillScore] is the number that matters: `1 − RMSE_model / RMSE_persistence`.
/// Zero means the model did exactly as well as assuming glucose stays where it
/// is, which is a strong baseline on a flat stretch — a positive score is the
/// model earning its place, a negative one is it doing harm.
class ForecastScore {
  const ForecastScore({
    required this.outcomes,
    required this.meanAbsoluteError,
    required this.rootMeanSquareError,
    required this.persistenceRootMeanSquareError,
    required this.bandCoverage,
  });

  final List<ForecastOutcome> outcomes;
  final double meanAbsoluteError;
  final double rootMeanSquareError;
  final double persistenceRootMeanSquareError;

  /// Share of readings that landed inside the q10–q90 band, or null when the
  /// model carries no band. A calibrated band sits near 0.8.
  final double? bandCoverage;

  int get matched => outcomes.length;

  double get skillScore => persistenceRootMeanSquareError == 0
      ? 0
      : 1 - rootMeanSquareError / persistenceRootMeanSquareError;
}

/// Scores past forecasts against the readings this device actually recorded.
///
/// The archive is keyed by absolute epoch-MINUTE and the forecasts sit on the
/// backend's five-minute grid, so the two rarely line up to the minute: each
/// target time takes the nearest reading within [tolerance] and forecasts with
/// no reading near their target are dropped rather than interpolated onto.
class ForecastAccuracy {
  ForecastAccuracy({
    required this.backtest,
    required this.archive,
    this.tolerance = const Duration(minutes: 3),
  });

  final ForecastBacktest backtest;

  /// The long-term glucose archive, epoch-minute -> mg/dL.
  final SplayTreeMap<int, int> archive;

  final Duration tolerance;

  /// The score, or null when no forecast in the window has a reading to be
  /// judged against — the ordinary state right after a sensor gap.
  ForecastScore? build() {
    final outcomes = _match();
    if (outcomes.isEmpty) {
      return null;
    }
    var absolute = 0.0;
    var squared = 0.0;
    var persistenceSquared = 0.0;
    var banded = 0;
    var covered = 0;
    for (final outcome in outcomes) {
      absolute += outcome.error.abs();
      squared += math.pow(outcome.error, 2);
      persistenceSquared += math.pow(outcome.persistence - outcome.actual, 2);
      if (outcome.lo != null && outcome.hi != null) {
        banded += 1;
        covered += outcome.isCovered ? 1 : 0;
      }
    }
    final count = outcomes.length;
    return ForecastScore(
      outcomes: outcomes,
      meanAbsoluteError: absolute / count,
      rootMeanSquareError: math.sqrt(squared / count),
      persistenceRootMeanSquareError: math.sqrt(persistenceSquared / count),
      bandCoverage: banded == 0 ? null : covered / banded,
    );
  }

  List<ForecastOutcome> _match() {
    final outcomes = <ForecastOutcome>[];
    for (final point in backtest.points) {
      final target =
          point.at
              .add(Duration(minutes: backtest.horizonMin))
              .millisecondsSinceEpoch ~/
          60000;
      final actual = _readingNear(target);
      if (actual == null) {
        continue;
      }
      outcomes.add(
        ForecastOutcome(
          at: point.at,
          predicted: point.predicted,
          persistence: point.persistence,
          actual: actual,
          lo: point.lo,
          hi: point.hi,
        ),
      );
    }
    return outcomes;
  }

  /// The reading closest to [minute], or null when the nearest one is further
  /// away than [tolerance].
  int? _readingNear(int minute) {
    final exact = archive[minute];
    if (exact != null) {
      return exact;
    }
    final before = archive.lastKeyBefore(minute);
    final after = archive.firstKeyAfter(minute);
    final nearest = _nearestOf(minute, before, after);
    if (nearest == null || (nearest - minute).abs() > tolerance.inMinutes) {
      return null;
    }
    return archive[nearest];
  }

  int? _nearestOf(int minute, int? before, int? after) {
    if (before == null || after == null) {
      return before ?? after;
    }
    return minute - before <= after - minute ? before : after;
  }
}
