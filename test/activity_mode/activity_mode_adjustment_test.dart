import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/activity_mode/activity_mode.dart';
import 'package:insulink/src/activity_mode/activity_mode_adjustment.dart';
import 'package:insulink/src/pump/loop/loop_algorithm.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/loop/loop_safety.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

import '../pump/loop_input.dart';

void main() {
  final now = DateTime(2026, 10, 15, 17);
  final running = PodStatusResponse(hex('1D1800A02800000463FF'));
  const endurance = ActivityModeAdjustment(
    mode: ActivityMode.endurance,
    targetMgdl: 150,
    basalPercent: 50,
  );
  const strength = ActivityModeAdjustment(
    mode: ActivityMode.strength,
    basalPercent: 150,
  );

  /// One cycle the way [PodLoopRunner] decides it: the mode moves the target
  /// and the anchor, the safety layer gets the real schedule of 1 U/h.
  LoopDecision decide(ActivityModeAdjustment activity, LoopLimits base) {
    final limits = activity.limits(base);
    final glucose = glucoseAt(now, mgdl: 110);
    return LoopSafety(limits).decide(
      wantedUnitsPerHour: LoopAlgorithm(limits).wantedUnitsPerHour(
        glucose: glucose,
        iobUnits: 0,
        scheduledUnitsPerHour: activity.anchor(1.0),
      ),
      glucose: glucose,
      iobUnits: 0,
      scheduledUnitsPerHour: 1.0,
      status: running,
      automatedUnitsLastHour: 0,
    );
  }

  test('endurance raises the target but never lowers it', () {
    expect(endurance.limits(limitsWith(targetMgdl: 110)).targetMgdl, 150);
    expect(endurance.limits(limitsWith(targetMgdl: 160)).targetMgdl, 160);
    expect(strength.limits(limitsWith(targetMgdl: 110)).targetMgdl, 110);
  });

  test('normal leaves the cycle exactly as it was', () {
    final decision = decide(const ActivityModeAdjustment.none(), limitsWith());

    expect(decision.unitsPerHour, 1.0);
    expect(decision.reason, LoopReason.holdingSchedule);
  });

  test('endurance at the everyday target backs off the schedule', () {
    final decision = decide(endurance, limitsWith());

    expect(decision.unitsPerHour, 0);
    expect(decision.reason, LoopReason.easingOff);
    expect(decision.scheduledUnitsPerHour, 1.0);
  });

  test('strength runs above the schedule, billed as a dose and capped', () {
    final decision = decide(strength, limitsWith(maxUnitsPerHour: 1.2));

    expect(decision.unitsPerHour, greaterThan(1.0));
    expect(decision.unitsPerHour, lessThanOrEqualTo(1.2));
    expect(decision.reason, LoopReason.correcting);
    expect(decision.boundBy, LoopBound.maxRate);
    expect(decision.excessUnitsOver(LoopLimits.fuse), greaterThan(0));
  });
}
