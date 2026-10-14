import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/loop/loop_algorithm.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/loop/loop_micro_bolus_limits.dart';
import 'package:insulink/src/pump/loop/loop_micro_bolus_safety.dart';
import 'package:insulink/src/pump/loop/loop_safety.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

import 'loop_input.dart';

void main() {
  final now = DateTime(2026, 5, 4, 9, 30);
  final running = PodStatusResponse(hex('1D1800A02800000463FF'));
  final bolusing = PodStatusResponse(hex('1D580519C00E0039A7FF8085'));

  LoopMicroBolusLimits microBolusWith({
    bool enabled = true,
    bool onlyRising = true,
    double maxUnits = 3.0,
    double share = 0.5,
    int fromMgdl = 120,
    Duration minInterval = const Duration(minutes: 5),
    double maxUnitsPerHour = 10,
  }) {
    return LoopMicroBolusLimits(
      enabled: enabled,
      onlyRising: onlyRising,
      maxUnits: maxUnits,
      shareOfMissing: share,
      fromMgdl: fromMgdl,
      minInterval: minInterval,
      maxUnitsPerHour: maxUnitsPerHour,
    );
  }

  /// One cycle through both safety layers, the way the runner composes them.
  /// The IOB ceiling is set out of the way unless a test is about it.
  LoopDecision decide({
    required int mgdl,
    double trendPerMinute = 2,
    double iobUnits = 0,
    double maxIobUnits = 20,
    double microBolusLastHour = 0,
    DateTime? lastMicroBolusAt,
    double? reservoirUnits,
    PodStatusResponse? status,
    LoopMicroBolusLimits? microBolus,
  }) {
    final base = limitsWith(maxIobUnits: maxIobUnits);
    final limits = LoopLimits(
      targetMgdl: base.targetMgdl,
      suspendBelowMgdl: base.suspendBelowMgdl,
      correctionFactorMgdl: base.correctionFactorMgdl,
      insulinDuration: base.insulinDuration,
      maxUnitsPerHour: base.maxUnitsPerHour,
      maxIobUnits: base.maxIobUnits,
      microBolus: microBolus ?? microBolusWith(),
    );
    final glucose = glucoseAt(now, mgdl: mgdl, trendPerMinute: trendPerMinute);
    final algorithm = LoopAlgorithm(limits);
    final decision = LoopSafety(limits).decide(
      wantedUnitsPerHour: algorithm.wantedUnitsPerHour(
        glucose: glucose,
        iobUnits: iobUnits,
        scheduledUnitsPerHour: 1.0,
      ),
      glucose: glucose,
      iobUnits: iobUnits,
      scheduledUnitsPerHour: 1.0,
      status: status ?? running,
      automatedUnitsLastHour: 0,
    );
    return LoopMicroBolusSafety(limits).apply(
      decision,
      correctionUnits: algorithm.correctionUnits(
        glucose: glucose,
        iobUnits: iobUnits,
      ),
      glucose: glucose,
      iobUnits: iobUnits,
      microBolusUnitsLastHour: microBolusLastHour,
      lastMicroBolusAt: lastMicroBolusAt,
      now: now,
      reservoirUnits: reservoirUnits,
    );
  }

  group('a micro bolus is only given when it is wanted', () {
    test('switched off, the loop corrects by rate alone', () {
      final decision = decide(
        mgdl: 220,
        microBolus: microBolusWith(enabled: false),
      );

      expect(decision.microBolusUnits, 0);
      expect(decision.reason, LoopReason.correcting);
    });

    test('a rising glucose above the threshold gets one', () {
      final decision = decide(mgdl: 220);

      expect(decision.microBolusUnits, greaterThan(0));
      expect(decision.reason, LoopReason.microBolusing);
    });

    test('below the user threshold nothing is given', () {
      final decision = decide(
        mgdl: 150,
        microBolus: microBolusWith(fromMgdl: 160),
      );

      expect(decision.microBolusUnits, 0);
    });

    test('a level glucose waits while only rising is set', () {
      expect(decide(mgdl: 220, trendPerMinute: 0).microBolusUnits, 0);
    });

    test('a level glucose is corrected once only rising is off', () {
      final decision = decide(
        mgdl: 220,
        trendPerMinute: 0,
        microBolus: microBolusWith(onlyRising: false),
      );

      expect(decision.microBolusUnits, greaterThan(0));
    });

    test('nothing is given while the pod is still bolusing', () {
      expect(decide(mgdl: 220, status: bolusing).microBolusUnits, 0);
    });

    test('nothing is given heading below target', () {
      final decision = decide(
        mgdl: 130,
        trendPerMinute: 0.5,
        iobUnits: 3,
        microBolus: microBolusWith(fromMgdl: 100),
      );

      expect(decision.microBolusUnits, 0);
    });

    test('a micro bolus inside the interval waits', () {
      final decision = decide(
        mgdl: 220,
        lastMicroBolusAt: now.subtract(const Duration(minutes: 10)),
        microBolus: microBolusWith(minInterval: const Duration(minutes: 15)),
      );

      expect(decision.microBolusUnits, 0);
    });

    /// Booked a few seconds into its cycle, so the next cycle sees slightly
    /// less than five minutes. That must not skip every second cycle.
    test('the next cycle is not skipped for a few seconds', () {
      final decision = decide(
        mgdl: 220,
        lastMicroBolusAt: now.subtract(const Duration(minutes: 4, seconds: 50)),
      );

      expect(decision.microBolusUnits, greaterThan(0));
    });
  });

  group('every ceiling holds the micro bolus down', () {
    /// 220 rising 2/min: 280 predicted, (280 - 110) / 35 = 4.857 U missing.
    test('only the share of the missing insulin is given', () {
      expect(decide(mgdl: 220).microBolusUnits, closeTo(2.40, 1e-9));
    });

    test('the largest single micro bolus', () {
      final decision = decide(
        mgdl: 220,
        microBolus: microBolusWith(maxUnits: 0.5),
      );

      expect(decision.microBolusUnits, closeTo(0.5, 1e-9));
      expect(decision.microBolusBoundBy, LoopBound.maxMicroBolus);
    });

    test('the micro-bolus insulin per hour', () {
      final decision = decide(
        mgdl: 220,
        microBolusLastHour: 2.7,
        microBolus: microBolusWith(maxUnitsPerHour: 3),
      );

      expect(decision.microBolusUnits, closeTo(0.3, 1e-9));
      expect(decision.microBolusBoundBy, LoopBound.microBolusHourly);
    });

    test('the active insulin ceiling', () {
      final decision = decide(mgdl: 220, iobUnits: 1, maxIobUnits: 1.5);

      expect(decision.microBolusUnits, closeTo(0.5, 1e-9));
      expect(decision.microBolusBoundBy, LoopBound.maxIob);
    });

    /// 125 mg/dL, 40 above the stop threshold at 35 per unit: 1.14 U fits in
    /// total, the whole of it at once rather than spread over the fuse.
    test('the whole micro bolus has to fit the hypo headroom', () {
      final decision = decide(
        mgdl: 125,
        trendPerMinute: 3,
        microBolus: microBolusWith(fromMgdl: 100, share: 1),
      );

      expect(decision.microBolusUnits, closeTo(1.10, 1e-9));
      expect(decision.microBolusBoundBy, LoopBound.hypoHeadroom);
    });

    test('the reservoir', () {
      final decision = decide(mgdl: 220, reservoirUnits: 0.3);

      expect(decision.microBolusUnits, closeTo(0.3, 1e-9));
    });

    test('the dose lands on the pulse grid, rounded down', () {
      final units = decide(
        mgdl: 220,
        microBolus: microBolusWith(maxUnits: 0.37),
      ).microBolusUnits;

      expect(units, closeTo(0.35, 1e-9));
    });
  });

  /// The micro bolus IS the correction. A rate above schedule next to it would
  /// give the same missing insulin twice.
  test('with a micro bolus the rate stays at the schedule', () {
    final decision = decide(mgdl: 220);

    expect(decision.microBolusUnits, greaterThan(0));
    expect(decision.unitsPerHour, 1.0);
  });
}
