import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/loop/loop_algorithm.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/loop/loop_glucose.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/loop/loop_safety.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

import 'loop_input.dart';

void main() {
  final now = DateTime(2026, 5, 4, 9, 30);

  // Captured pod statuses, the same frames the delivery-guard tests use.
  // Running above minimum volume, delivering basal.
  final running = PodStatusResponse(hex('1D1800A02800000463FF'));
  // Running, with 14 bolus pulses still to deliver.
  final bolusing = PodStatusResponse(hex('1D580519C00E0039A7FF8085'));
  // Running below minimum volume, 979 pulses (48.95 U) left.
  final lowReservoir = PodStatusResponse(hex('1D1905281000004387D3039A'));

  LoopDecision decide({
    required int mgdl,
    double trendPerMinute = 0,
    double iobUnits = 0,
    double schedule = 1.0,
    double automatedLastHour = 0,
    LoopLimits? limits,
    PodStatusResponse? status,
    double? reservoirUnits,
  }) {
    final applied = limits ?? limitsWith();
    final glucose =
        glucoseAt(now, mgdl: mgdl, trendPerMinute: trendPerMinute);
    final wanted = LoopAlgorithm(applied).wantedUnitsPerHour(
      glucose: glucose,
      iobUnits: iobUnits,
      scheduledUnitsPerHour: schedule,
    );
    return LoopSafety(applied).decide(
      wantedUnitsPerHour: wanted,
      glucose: glucose,
      iobUnits: iobUnits,
      scheduledUnitsPerHour: schedule,
      status: status ?? running,
      automatedUnitsLastHour: automatedLastHour,
      reservoirUnits: reservoirUnits,
    );
  }

  group('glucose alone can stop delivery', () {
    test('at or below the suspend threshold nothing is delivered', () {
      for (final mgdl in [85, 80, 70, 55, 40]) {
        final decision = decide(mgdl: mgdl);

        expect(decision.unitsPerHour, 0, reason: '$mgdl should suspend');
        expect(decision.reason, LoopReason.suspendedLow);
      }
    });

    /// The value is fine right now; the trend is not. Waiting for the number to
    /// arrive before stopping means stopping too late, because insulin already
    /// given keeps working.
    test('a fall heading under the threshold suspends before it gets there', () {
      final decision = decide(mgdl: 130, trendPerMinute: -2.0);

      expect(decision.unitsPerHour, 0);
      expect(decision.reason, LoopReason.suspendedFalling);
    });

    test('a fall that levels out above the threshold does not suspend', () {
      final decision = decide(mgdl: 200, trendPerMinute: -1.0);

      expect(decision.reason, isNot(LoopReason.suspendedFalling));
    });

    /// A suspend is a decision, not a clamped rate, so nothing about the pod or
    /// the ceilings can turn it back into a delivery.
    test('a suspend outranks every ceiling', () {
      final decision = decide(
        mgdl: 60,
        schedule: 2.0,
        limits: limitsWith(maxUnitsPerHour: 10),
      );

      expect(decision.unitsPerHour, 0);
      expect(decision.boundBy, isNull);
    });
  });

  group('the rate follows the glucose', () {
    test('above target it goes above the schedule', () {
      final decision = decide(mgdl: 250, schedule: 1.0);

      expect(decision.reason, LoopReason.correcting);
      expect(decision.unitsPerHour, greaterThan(1.0));
    });

    test('on target it is the schedule', () {
      final decision = decide(mgdl: 110, schedule: 1.0);

      expect(decision.reason, LoopReason.holdingSchedule);
      expect(decision.unitsPerHour, closeTo(1.0, 0.05));
    });

    test('below target but above the threshold it eases off', () {
      final decision = decide(mgdl: 95, schedule: 1.0);

      expect(decision.reason, LoopReason.easingOff);
      expect(decision.unitsPerHour, lessThan(1.0));
    });

    test('the rate is never negative', () {
      final decision = decide(mgdl: 95, schedule: 0.05);

      expect(decision.unitsPerHour, greaterThanOrEqualTo(0));
    });
  });

  group('each ceiling holds, and says that it did', () {
    test('the configured rate ceiling', () {
      final decision = decide(
        mgdl: 400,
        schedule: 1.0,
        limits: limitsWith(maxUnitsPerHour: 2.0),
      );

      expect(decision.unitsPerHour, 2.0);
      expect(decision.boundBy, LoopBound.maxRate);
    });

    /// The case the hypo ceiling exists for, and the one the arithmetic alone
    /// gets wrong: glucose just above the threshold and rising. The trend says
    /// correct the rise; the distance to the threshold says there is almost
    /// nothing to spend. The second wins.
    test('the room left above the suspend threshold', () {
      final decision = decide(mgdl: 90, trendPerMinute: 2.0, schedule: 1.0);

      expect(decision.boundBy, LoopBound.hypoHeadroom);
      expect(decision.unitsPerHour, closeTo(1.25, 1e-9));
    });

    /// Insulin already working has first claim on that room. Once it exceeds
    /// what fits, the automation may not add to it at all.
    test('insulin already working uses that room up', () {
      final decision =
          decide(mgdl: 150, trendPerMinute: 2.0, iobUnits: 2.0, schedule: 1.0);

      expect(decision.unitsPerHour, lessThanOrEqualTo(1.0));
    });

    test('the insulin-on-board ceiling', () {
      final decision = decide(
        mgdl: 400,
        iobUnits: 4.9,
        limits: limitsWith(maxIobUnits: 5.0, maxUnitsPerHour: 30),
      );

      expect(decision.boundBy, LoopBound.maxIob);
      expect(decision.unitsPerHour, lessThanOrEqualTo(1.0 + 0.1 / 0.5));
    });

    test('the rolling hourly ceiling', () {
      final decision = decide(
        mgdl: 400,
        schedule: 1.0,
        automatedLastHour: 2.9,
        limits: limitsWith(maxUnitsPerHour: 3.0),
      );

      expect(decision.boundBy, LoopBound.hourlyCeiling);
      expect(decision.unitsPerHour, lessThan(1.5));
    });

    test('what is left in the reservoir', () {
      final decision = decide(
        mgdl: 400,
        schedule: 1.0,
        reservoirUnits: 0.5,
        limits: limitsWith(maxUnitsPerHour: 10),
      );

      expect(decision.boundBy, LoopBound.reservoir);
      expect(decision.unitsPerHour, closeTo(1.0, 1e-9));
    });

    test('a spent hourly budget leaves only the schedule', () {
      final decision = decide(
        mgdl: 400,
        schedule: 1.0,
        automatedLastHour: 3.0,
        limits: limitsWith(maxUnitsPerHour: 3.0),
      );

      expect(decision.unitsPerHour, closeTo(1.0, 1e-9));
    });
  });

  group('the pod must be able to deliver', () {
    test('a pod already running a bolus is not commanded', () {
      final decision = decide(mgdl: 250, status: bolusing);

      expect(decision.reason, LoopReason.podUnavailable);
      expect(decision.isActionable, isFalse);
    });

    test('a pod low on insulin still delivers', () {
      final decision = decide(mgdl: 250, status: lowReservoir);

      expect(decision.isActionable, isTrue);
    });
  });

  group('unusable inputs decide nothing at all', () {
    test('a sensor that cannot be trusted', () {
      final limits = limitsWith();
      final decision = LoopSafety(limits).decide(
        wantedUnitsPerHour: 5.0,
        glucose: LoopGlucose.from(
          archiveEndingAt(now.subtract(const Duration(hours: 2)), mgdl: 250),
          now: now,
        ),
        iobUnits: 0,
        scheduledUnitsPerHour: 1.0,
        status: running,
        automatedUnitsLastHour: 0,
      );

      expect(decision.reason, LoopReason.noGlucose);
      expect(decision.isActionable, isFalse);
    });

    /// A limit set that contradicts itself cannot be clamped into one that does
    /// not, so the loop refuses rather than picking a number.
    test('limits that do not make sense', () {
      final decision = decide(
        mgdl: 250,
        limits: limitsWith(targetMgdl: 100, suspendBelowMgdl: 120),
      );

      expect(decision.reason, LoopReason.limitsInvalid);
      expect(decision.isActionable, isFalse);
    });
  });

  group('the rate lands on the pod grid', () {
    test('it is a whole number of 0.05 U/h steps', () {
      for (var mgdl = 90; mgdl <= 400; mgdl += 7) {
        final rate = decide(mgdl: mgdl, schedule: 0.85).unitsPerHour;

        expect((rate * 20 - (rate * 20).round()).abs(), lessThan(1e-9),
            reason: '$rate U/h is off the 0.05 grid');
      }
    });

    /// Rounding to nearest would let a rate that a ceiling had just brought
    /// under a limit step back over it.
    test('snapping only ever rounds down', () {
      expect(LoopSafety.snapToPodGrid(0.049), 0);
      expect(LoopSafety.snapToPodGrid(0.099), closeTo(0.05, 1e-9));
      expect(LoopSafety.snapToPodGrid(2.999), closeTo(2.95, 1e-9));
      expect(LoopSafety.snapToPodGrid(-1), 0);
    });
  });
}
