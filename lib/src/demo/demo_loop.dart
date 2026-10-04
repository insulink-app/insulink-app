import 'dart:collection';

import 'package:insulink/src/injection/active_insulin.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_store.dart';
import 'package:insulink/src/pump/loop/loop_algorithm.dart';
import 'package:insulink/src/pump/loop/loop_glucose.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/loop/loop_safety.dart';
import 'package:insulink/src/pump/pod_basal_delivery.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

/// Automated delivery switched on for the demo pod, with the last two hours of
/// cycles already behind it, so the pump page shows the automation running and
/// the rate it is delivering right now.
///
/// Each cycle reaches the pod, so it is also an entry in the pod's contact log.
/// Every cycle is decided by the real [LoopAlgorithm] and [LoopSafety] from the
/// demo glucose, the way the service's runner decides it, and recorded as
/// delivered with the temporary rate it would have programmed. Insulin on board
/// is the meal boluses plus the automation's own, as in the service's runner.
class DemoLoop {
  DemoLoop({
    required this.store,
    required this.readings,
    required this.status,
    required this.now,
  });

  final PodStore store;
  final Map<DateTime, int> readings;
  final PodStatusResponse status;
  final DateTime now;

  static const int cycleCount = 24;
  static const Duration cycleEvery = Duration(minutes: 5);

  /// More than the loop reads for its trend, so each archive stays small.
  static const Duration recentHistory = Duration(hours: 2);

  Future<void> engage() async {
    final limits = await LoopLimits.load();
    final meals = await const MealStore().loadMeals();
    await store.saveLoopMode(PodLoopMode.engaged);
    for (var index = cycleCount - 1; index >= 0; index--) {
      await _cycle(limits, meals, now.subtract(cycleEvery * index));
    }
  }

  Future<void> _cycle(LoopLimits limits, List<Meal> meals, DateTime at) async {
    await store.markSeen(at);
    final glucose = LoopGlucose.from(_archiveUpTo(at), now: at);
    final iob =
        ActiveInsulin(limits.insulinDuration).units(meals, now: at) +
        store.loopIobUnits(limits.insulinDuration, now: at);
    final schedule = store.scheduledUnitsPerHourAt(at) ?? 0;
    final decision = LoopSafety(limits).decide(
      wantedUnitsPerHour: LoopAlgorithm(limits).wantedUnitsPerHour(
        glucose: glucose,
        iobUnits: iob,
        scheduledUnitsPerHour: schedule,
      ),
      glucose: glucose,
      iobUnits: iob,
      scheduledUnitsPerHour: schedule,
      status: status,
      automatedUnitsLastHour: store.automatedUnitsWithin(
        const Duration(hours: 1),
        now: at,
      ),
      reservoirUnits: status.reservoirUnits,
    );
    await store.recordLoopCycle(
      PodLoopCycle(
        at: at,
        unitsPerHour: decision.unitsPerHour,
        scheduledUnitsPerHour: decision.scheduledUnitsPerHour,
        reason: decision.reason,
        delivered: decision.isActionable,
        boundBy: decision.boundBy,
        mgdl: decision.mgdl,
        trendPerMinute: decision.trendPerMinute,
        iobUnits: decision.iobUnits,
      ),
    );
    if (decision.isActionable) {
      await store.saveTemporaryBasal(
        PodTemporaryBasal(
          unitsPerHour: decision.unitsPerHour,
          start: at,
          end: at.add(LoopLimits.fuse),
          automated: true,
        ),
      );
    }
  }

  /// The recent readings up to [at], keyed by epoch minute like the CGM archive.
  SplayTreeMap<int, int> _archiveUpTo(DateTime at) => SplayTreeMap.of({
    for (final entry in readings.entries)
      if (!entry.key.isAfter(at) && at.difference(entry.key) < recentHistory)
        entry.key.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute:
            entry.value,
  });
}
