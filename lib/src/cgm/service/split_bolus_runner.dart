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
  ///
  /// Must not run twice at once in one isolate (the caller guards it): a pod
  /// session can outlast the 30 s tick, and a second run would read a part
  /// still marked as sending as a send that died.
  Future<bool> run() async {
    final store = await PodStore.open();
    final plan = store.splitBolus;
    final now = DateTime.now();
    if (plan == null) {
      return false;
    }
    if (plan.sendingSince != null) {
      return _dropStranded(store, plan);
    }
    if (plan.parts.first.at.isAfter(now)) {
      return false;
    }
    if (!store.hasPod || plan.missedAt(now)) {
      return _abandon(store, 'alarm.split_bolus.lapsed');
    }
    return _give(store, plan);
  }

  /// A part a dead process was sending. It may have gone in, so it is never
  /// sent again; the delivery path left its pending record for the app to
  /// resolve, and the rest of the plan carries on.
  Future<bool> _dropStranded(PodStore store, SplitBolusPlan plan) async {
    await _saveRest(store, plan);
    return true;
  }

  /// Marks the first part as sending, sends it, then settles the plan against
  /// what the store holds NOW: the user may have cancelled meanwhile, or even
  /// started a new plan, and neither is touched. A dose that went in is logged
  /// either way.
  Future<bool> _give(PodStore store, SplitBolusPlan plan) async {
    final mark = DateTime.now();
    await store.saveSplitBolus(plan.sendingAt(mark));
    final outcome = await _send(store, plan.parts.first);
    await store.reload();
    final current = store.splitBolus;
    final ours = current?.sendingSince == mark ? current : null;
    if (outcome.recordedUnits > 0) {
      await _logDose(outcome, plan.glucoseMgdl);
      if (ours != null) {
        await _saveRest(store, ours);
      }
      return true;
    }
    if (ours == null) {
      return true;
    }
    if (_busyKeys.contains(outcome.detailKey)) {
      await store.saveSplitBolus(ours.settled);
      return false;
    }
    return _abandon(store, 'alarm.split_bolus.failed');
  }

  Future<BolusDeliveryResult> _send(PodStore store, SplitBolusPart part) async {
    final delivery = await AdvisoryActionRunner(_alarms).serviceDelivery(store);
    return delivery.deliver(
      part.units,
      deliveredLastHour: store.bolusUnitsWithin(const Duration(hours: 1)),
    );
  }

  /// Drops the first part, or the whole plan when that was the last.
  Future<void> _saveRest(PodStore store, SplitBolusPlan plan) async {
    final rest = plan.afterFirst;
    if (rest == null) {
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
