import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/loop/loop_glucose.dart';

import 'loop_input.dart';

void main() {
  final now = DateTime(2026, 5, 4, 9, 30);

  group('data that may not be dosed on is refused', () {
    test('an empty archive', () {
      final glucose = LoopGlucose.from(SplayTreeMap<int, int>(), now: now);

      expect(glucose.isUsable, isFalse);
      expect(glucose.problem, LoopGlucoseProblem.noReadings);
    });

    /// The sensor going quiet is the ordinary failure, and the one that must
    /// never be dosed through: the last value says nothing about the glucose
    /// now.
    test('a reading older than the maximum age', () {
      final stale = now.subtract(const Duration(minutes: 13));

      final glucose = LoopGlucose.from(
        archiveEndingAt(stale, mgdl: 180),
        now: now,
      );

      expect(glucose.problem, LoopGlucoseProblem.stale);
    });

    test('a reading just inside the maximum age is still usable', () {
      final recent = now.subtract(const Duration(minutes: 11));

      final glucose = LoopGlucose.from(
        archiveEndingAt(recent, mgdl: 180),
        now: now,
      );

      expect(glucose.isUsable, isTrue);
    });

    /// Two clocks that disagree make every age meaningless, including the one
    /// the staleness check just ran.
    test('a reading stamped well ahead of the clock', () {
      final ahead = now.add(const Duration(minutes: 5));

      final glucose = LoopGlucose.from(
        archiveEndingAt(ahead, mgdl: 180),
        now: now,
      );

      expect(glucose.problem, LoopGlucoseProblem.fromTheFuture);
    });

    test('a value outside what a body can be', () {
      for (final mgdl in [10, 25, 520, 900]) {
        final glucose = LoopGlucose.from(
          archiveEndingAt(now, mgdl: mgdl),
          now: now,
        );

        expect(glucose.problem, LoopGlucoseProblem.implausibleValue,
            reason: '$mgdl should be refused');
      }
    });

    test('too few points to measure a trend from', () {
      final glucose = LoopGlucose.from(
        archiveEndingAt(now, mgdl: 180, points: 2),
        now: now,
      );

      expect(glucose.problem, LoopGlucoseProblem.notEnoughHistory);
    });

    /// A jump this size is a sensor artefact, and acting on the trend it implies
    /// would be acting on noise.
    test('a physiologically impossible rate of change', () {
      final glucose = LoopGlucose.from(
        archiveEndingAt(now, mgdl: 300, trendPerMinute: 9.0),
        now: now,
      );

      expect(glucose.problem, LoopGlucoseProblem.implausibleTrend);
    });
  });

  group('the trend is measured, not taken on trust', () {
    test('a flat sensor reads as no trend', () {
      expect(glucoseAt(now, mgdl: 140).trendPerMinute, closeTo(0, 1e-9));
    });

    test('a falling sensor reads as a negative trend', () {
      final glucose = glucoseAt(now, mgdl: 140, trendPerMinute: -2.0);

      expect(glucose.trendPerMinute, closeTo(-2.0, 1e-9));
      expect(glucose.mgdl, 140);
    });

    test('a rising sensor reads as a positive trend', () {
      expect(glucoseAt(now, mgdl: 140, trendPerMinute: 1.0).trendPerMinute,
          closeTo(1.0, 1e-9));
    });

    /// One bad point must not set the trend. Reading the same data from its two
    /// endpoints gives -3.0/min, which would suspend a loop on a sensor that is
    /// barely moving, and least squares gives -2.6 because the outlier sits
    /// where it has the most leverage. The pairwise median holds the -1.0 the
    /// other four points agree on. The hypo prediction leans on this number.
    test('a single noisy point does not take over the trend', () {
      final archive = archiveEndingAt(now, mgdl: 140, trendPerMinute: -1.0);
      final oldest = archive.firstKey()!;
      archive[oldest] = archive[oldest]! + 40;

      final glucose = LoopGlucose.from(archive, now: now);

      final acrossEndpoints = (archive[archive.lastKey()!]! - archive[oldest]!) / 20;
      expect(acrossEndpoints, closeTo(-3.0, 1e-9));
      expect(glucose.trendPerMinute, closeTo(-1.0, 1e-9));
    });

    test('the projection follows the measured trend', () {
      final glucose = glucoseAt(now, mgdl: 140, trendPerMinute: -1.0);

      expect(glucose.projected(30), closeTo(110, 1e-6));
    });
  });
}
