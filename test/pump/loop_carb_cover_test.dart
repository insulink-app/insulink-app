import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/loop/loop_algorithm.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/loop/loop_safety.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

import 'loop_input.dart';

/// The day that prompted it: glucose rising past 200 two hours after a meal
/// whose bolus is still on board. Counted as correction insulin, that bolus
/// had the loop predict a low and withhold even the scheduled basal.
void main() {
  final now = DateTime(2026, 10, 22, 16, 30);
  final running = PodStatusResponse(hex('1D1800A02800000463FF'));
  const schedule = 0.2;
  const mealIob = 2.3;

  LoopDecision decide({required double carbCovered, double maxIob = 5}) {
    final limits = limitsWith(
      targetMgdl: 127,
      suspendBelowMgdl: 100,
      correctionFactorMgdl: 80,
      maxUnitsPerHour: 1,
      maxIobUnits: maxIob,
    );
    final glucose = glucoseAt(now, mgdl: 206, trendPerMinute: 1);
    final uncovered = LoopSafety.uncoveredIob(mealIob, carbCovered);
    return LoopSafety(limits).decide(
      wantedUnitsPerHour: LoopAlgorithm(limits).wantedUnitsPerHour(
        glucose: glucose,
        iobUnits: uncovered,
        scheduledUnitsPerHour: schedule,
      ),
      glucose: glucose,
      iobUnits: mealIob,
      scheduledUnitsPerHour: schedule,
      status: running,
      automatedUnitsLastHour: 0,
      carbCoveredUnits: carbCovered,
    );
  }

  test('a meal bolus read as correction withholds all insulin', () {
    final decision = decide(carbCovered: 0);

    expect(decision.unitsPerHour, 0);
    expect(decision.reason, LoopReason.easingOff);
  });

  test('a meal bolus matched by its carbs leaves room to correct', () {
    final decision = decide(carbCovered: mealIob);

    expect(decision.unitsPerHour, 1);
    expect(decision.reason, LoopReason.correcting);
    expect(decision.eventualMgdl, greaterThan(200));
  });

  test('the insulin-on-board ceiling still counts the meal bolus', () {
    final decision = decide(carbCovered: mealIob, maxIob: 2);

    expect(decision.unitsPerHour, closeTo(schedule, 1e-9));
    expect(decision.boundBy, LoopBound.maxIob);
  });

  test('covered insulin never goes below zero', () {
    expect(LoopSafety.uncoveredIob(1, 3), 0);
    expect(LoopSafety.uncoveredIob(3, 1), 2);
  });
}
