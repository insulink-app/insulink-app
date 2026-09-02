import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/analysis/forecast/forecast_accuracy.dart';
import 'package:insulink/src/analysis/forecast/forecast_backtest.dart';

/// The archive as the app keeps it: absolute epoch-MINUTE -> mg/dL.
SplayTreeMap<int, int> archiveOf(Map<int, int> readings) =>
    SplayTreeMap<int, int>.of(readings);

DateTime atMinute(int minute) =>
    DateTime.fromMillisecondsSinceEpoch(minute * 60000, isUtc: true);

BacktestPoint point(
  int minute, {
  required int predicted,
  required int persistence,
  int? lo,
  int? hi,
}) =>
    BacktestPoint(
      at: atMinute(minute),
      predicted: predicted,
      persistence: persistence,
      lo: lo,
      hi: hi,
    );

void main() {
  ForecastScore? score(List<BacktestPoint> points, Map<int, int> readings) =>
      ForecastAccuracy(
        backtest: ForecastBacktest(horizonMin: 30, points: points),
        archive: archiveOf(readings),
      ).build();

  group('scoring a forecast against what the sensor read', () {
    test('each point is judged at its own target time, not at its anchor', () {
      final result = score(
        [point(0, predicted: 150, persistence: 120)],
        {0: 120, 30: 140},
      )!;

      expect(result.matched, 1);
      expect(result.outcomes.single.actual, 140);
      expect(result.meanAbsoluteError, 10);
    });

    /// The number the ROADMAP scores every model by: better than "it stays
    /// where it is" or it is not worth having.
    test('the skill score is positive when the model beats persistence', () {
      final result = score(
        [
          point(0, predicted: 138, persistence: 120),
          point(5, predicted: 148, persistence: 125),
        ],
        {30: 140, 35: 150},
      )!;

      expect(result.skillScore, greaterThan(0));
      expect(result.rootMeanSquareError,
          lessThan(result.persistenceRootMeanSquareError));
    });

    test('a forecast no better than persistence scores zero', () {
      final result = score(
        [point(0, predicted: 120, persistence: 120)],
        {30: 140},
      )!;

      expect(result.skillScore, 0);
    });

    test('coverage counts the readings that landed inside the band', () {
      final result = score(
        [
          point(0, predicted: 130, persistence: 120, lo: 120, hi: 160),
          point(5, predicted: 130, persistence: 120, lo: 120, hi: 135),
        ],
        {30: 140, 35: 190},
      )!;

      expect(result.bandCoverage, 0.5);
    });

    test('a model without a band reports no coverage rather than zero', () {
      expect(
        score([point(0, predicted: 130, persistence: 120)], {30: 140})!
            .bandCoverage,
        isNull,
      );
    });
  });

  group('matching forecasts to readings', () {
    /// The sensor does not read on the backend's five-minute grid, so the
    /// nearest reading counts — but only a genuinely near one.
    test('the nearest reading within tolerance is used', () {
      final result = score(
        [point(0, predicted: 150, persistence: 120)],
        {28: 138, 32: 200},
      )!;

      expect(result.outcomes.single.actual, 138);
    });

    test('a target with no reading near it is dropped, not interpolated onto',
        () {
      expect(
        score(
          [point(0, predicted: 150, persistence: 120)],
          {0: 120, 45: 190},
        ),
        isNull,
      );
    });

    test('a window nothing can be scored in is null, not a zero-error score',
        () {
      expect(score([point(0, predicted: 150, persistence: 120)], {}), isNull);
    });
  });
}
