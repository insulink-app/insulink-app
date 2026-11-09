import '../../injection/bolus_delivery.dart';
import '../../nutrition/meal/meal.dart';
import '../../nutrition/meal/meal_store.dart';
import '../../nutrition/nutrition_sync.dart';
import '../../pump/pod_store.dart';
import '../../pump/split_bolus.dart';
import 'advisory_action_runner.dart';
import 'alarms.dart';

/// Gives the parts of a split bolus as they fall due. Runs in the service
/// isolate on the watchdog tick, chained after the notification actions so the
/// two never open a pod session side by side.
///
/// A part the pod is busy for (a micro bolus, the user's own bolus) waits for
/// the next tick. Any other failure, and a part that missed its time by more
/// than [SplitBolusPlan.lateAfter], ends the whole plan and SAYS so: the user
/// expects that insulin, and silence would read as if it went in.
class SplitBolusRunner {
  const SplitBolusRunner(this._alarms);

  final G7AlarmManager _alarms;

  /// Refusals that only mean "not now".
  static const _busyKeys = {
    'pump.bolus.already_running',
    'pump.bolus.queue_too_long',
  };

  /// Gives the part that is due, if any. Returns whether something changed, so
  /// the caller can tell the UI to re-read.
  Future<bool> run() async {
    final store = await PodStore.open();
    final plan = store.splitBolus;
    final now = DateTime.now();
    if (plan == null || plan.parts.first.at.isAfter(now)) {
      return false;
    }
    final late = now.difference(plan.parts.first.at) > SplitBolusPlan.lateAfter;
    if (!store.hasPod || late) {
      return _abandon(store, 'alarm.split_bolus.lapsed');
    }
    return _give(store, plan);
  }

  /// Sends the first part, then books it and moves the plan on.
  Future<bool> _give(PodStore store, SplitBolusPlan plan) async {
    final part = plan.parts.first;
    final delivery = await AdvisoryActionRunner(_alarms).serviceDelivery(store);
    final outcome = await delivery.deliver(
      part.units,
      deliveredLastHour: store.bolusUnitsWithin(const Duration(hours: 1)),
    );
    if (_busyKeys.contains(outcome.detailKey)) {
      return false;
    }
    if (outcome.recordedUnits <= 0) {
      return _abandon(store, 'alarm.split_bolus.failed');
    }
    await _advance(store, plan);
    await _logDose(outcome, plan.glucoseMgdl);
    return true;
  }

  /// Drops the given part. Re-read first: a plan the user cancelled while the
  /// part was on its way stays cancelled.
  Future<void> _advance(PodStore store, SplitBolusPlan plan) async {
    await store.reload();
    final rest = plan.afterFirst;
    if (store.splitBolus == null || rest == null) {
      await store.clearSplitBolus();
      return;
    }
    await store.saveSplitBolus(rest);
  }

  Future<bool> _abandon(PodStore store, String bodyKey) async {
    await store.clearSplitBolus();
    await _alarms.notifyAdvisoryOutcome(bodyKey, const []);
    return true;
  }

  /// Logs the part as its own insulin-only entry, then pushes it so the next
  /// pull does not replace it away.
  Future<void> _logDose(BolusDeliveryResult outcome, int glucoseMgdl) async {
    const store = MealStore();
    final meals = await store.loadMeals();
    meals.add(
      Meal(
        time: DateTime.now(),
        carbs: 0,
        glucoseMgdl: glucoseMgdl,
        bolus: outcome.recordedUnits,
        entries: const [],
        deliveredByPump: true,
      ),
    );
    await store.saveMeals(meals);
    NutritionSync().pushMeals();
  }
}
