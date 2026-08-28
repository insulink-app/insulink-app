import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/loop/loop_algorithm.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/loop/loop_safety.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

import 'loop_input.dart';

/// The property the whole feature is built to hold, checked by sweep rather than
/// by example.
///
/// The automation can only ever add insulin as a temporary rate that lasts one
/// fuse. So the worst thing it can do with a single decision is have that rate
/// run unattended for the entire fuse, which is exactly what happens if the phone
/// dies the moment after programming. The claim is that even then, the insulin it
/// added cannot take glucose below the threshold it is supposed to stop at.
///
/// Stated as arithmetic over the decision's own inputs:
///
///     reference - (iob + excess) * correctionFactor  >=  suspendBelow
///
/// where `reference` is the lower of glucose now and where the trend puts it at
/// the end of the fuse, and `excess` is what the rate delivers above the user's
/// own schedule across that fuse. Scheduled basal is not in `excess` on purpose:
/// it is the user's own maintenance rate, it runs whether the loop does or not,
/// and the loop withholding it would be its own kind of harm.
void main() {
  final now = DateTime(2026, 5, 4, 9, 30);
  final running = PodStatusResponse(hex('1D1800A02800000463FF'));

  LoopDecision decideWith({
    required LoopLimits limits,
    required int mgdl,
    required double trendPerMinute,
    required double iobUnits,
    required double schedule,
  }) {
    final glucose = glucoseAt(now, mgdl: mgdl, trendPerMinute: trendPerMinute);
    final wanted = LoopAlgorithm(limits).wantedUnitsPerHour(
      glucose: glucose,
      iobUnits: iobUnits,
      scheduledUnitsPerHour: schedule,
    );
    return LoopSafety(limits).decide(
      wantedUnitsPerHour: wanted,
      glucose: glucose,
      iobUnits: iobUnits,
      scheduledUnitsPerHour: schedule,
      status: running,
      automatedUnitsLastHour: 0,
    );
  }

  test('no decision can add enough insulin to reach the suspend threshold', () {
    var checked = 0;
    var delivered = 0;

    for (final correctionFactor in [10, 20, 35, 60, 100]) {
      for (final suspendBelow in [70, 85, 100]) {
        final limits = limitsWith(
          correctionFactorMgdl: correctionFactor,
          suspendBelowMgdl: suspendBelow,
          targetMgdl: suspendBelow + 25,
          maxUnitsPerHour: 30,
          maxIobUnits: 25,
        );
        for (var mgdl = 40; mgdl <= 400; mgdl += 5) {
          for (final trend in [-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0]) {
            for (final iob in [0.0, 1.0, 2.5, 5.0, 9.0]) {
              for (final schedule in [0.0, 0.5, 1.0, 2.5]) {
                final decision = decideWith(
                  limits: limits,
                  mgdl: mgdl,
                  trendPerMinute: trend,
                  iobUnits: iob,
                  schedule: schedule,
                );
                checked++;
                final excess = decision.excessUnitsOver(LoopLimits.fuse);
                if (excess <= 0) {
                  continue;
                }
                delivered++;
                final projected = mgdl + trend * LoopLimits.fuse.inMinutes;
                final reference = projected < mgdl ? projected : mgdl.toDouble();
                final worstCase =
                    reference - (iob + excess) * limits.correctionFactorMgdl;

                expect(
                  worstCase,
                  greaterThanOrEqualTo(limits.suspendBelowMgdl - 1e-6),
                  reason: 'glucose $mgdl, trend $trend, iob $iob, '
                      'schedule $schedule, factor $correctionFactor: '
                      'rate ${decision.unitsPerHour} adds $excess U over the '
                      'fuse and would reach $worstCase mg/dL',
                );
                expect(
                  decision.unitsPerHour,
                  lessThanOrEqualTo(limits.maxUnitsPerHour),
                );
              }
            }
          }
        }
      }
    }

    expect(checked, greaterThan(10000));
    expect(delivered, greaterThan(500),
        reason: 'a loop that never delivers would pass this vacuously');
  });

  test('below the threshold nothing is ever delivered, whatever else is true',
      () {
    for (final correctionFactor in [10, 35, 100]) {
      final limits = limitsWith(
        correctionFactorMgdl: correctionFactor,
        suspendBelowMgdl: 85,
        maxUnitsPerHour: 30,
      );
      for (var mgdl = 35; mgdl <= 85; mgdl += 1) {
        for (final schedule in [0.0, 1.0, 3.0]) {
          final decision = decideWith(
            limits: limits,
            mgdl: mgdl,
            trendPerMinute: 0,
            iobUnits: 0,
            schedule: schedule,
          );

          expect(decision.unitsPerHour, 0,
              reason: 'glucose $mgdl with schedule $schedule must suspend');
          expect(decision.reason, LoopReason.suspendedLow);
        }
      }
    }
  });

  /// Rising off a low is the case where stopping feels least necessary and is
  /// most necessary: the insulin that caused the fall is still working, so the
  /// rise says nothing about where it ends up.
  ///
  /// The sweep above cannot cover it, because building a rising history under a
  /// low value needs earlier readings below what a body can be, and those are
  /// refused before any decision is made. So it is checked here, just under the
  /// threshold, where the history stays inside the plausible range.
  test('a low that is already rising still suspends', () {
    final limits = limitsWith(suspendBelowMgdl: 85, maxUnitsPerHour: 30);

    for (final trend in [1.0, 2.0, 3.0]) {
      final decision = decideWith(
        limits: limits,
        mgdl: 84,
        trendPerMinute: trend,
        iobUnits: 0,
        schedule: 1.0,
      );

      expect(decision.unitsPerHour, 0, reason: 'rising at $trend still suspends');
      expect(decision.reason, LoopReason.suspendedLow);
    }
  });

  /// A sensor stuck at a high value is the shape a runaway takes: every cycle
  /// sees the same excursion and asks for another correction. What stops it is
  /// the loop counting its own insulin, so the sweep runs the cycles forward and
  /// feeds each decision back in as insulin on board.
  test('a sensor stuck high cannot make the loop stack insulin', () {
    final limits = limitsWith(maxUnitsPerHour: 3.0, maxIobUnits: 5.0);
    final fuseHours = LoopLimits.fuse.inMinutes / Duration.minutesPerHour;
    const cycleHours = 5 / 60;
    var iob = 0.0;
    var totalExcess = 0.0;

    for (var cycle = 0; cycle < 24; cycle++) {
      final decision = decideWith(
        limits: limits,
        mgdl: 350,
        trendPerMinute: 0,
        iobUnits: iob,
        schedule: 1.0,
      );
      final excessThisCycle =
          decision.excessUnitsOver(LoopLimits.fuse) / fuseHours * cycleHours;
      totalExcess += excessThisCycle;
      iob += excessThisCycle;
    }

    expect(iob, lessThanOrEqualTo(limits.maxIobUnits + 1e-6));
    expect(totalExcess, lessThanOrEqualTo(limits.maxIobUnits + 1e-6));
  });
}
