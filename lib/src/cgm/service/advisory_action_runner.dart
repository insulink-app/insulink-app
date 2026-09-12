import 'package:flutter/foundation.dart';

import '../../injection/bolus_delivery.dart';
import '../../nutrition/meal/meal.dart';
import '../../nutrition/meal/meal_store.dart';
import '../../nutrition/nutrition_sync.dart';
import '../../profile/bolus/profile_bolus_state.dart';
import '../../pump/pod_connection.dart';
import '../../pump/pod_controller.dart';
import '../../pump/pod_store.dart';
import '../../pump/service/pod_monitor.dart';
import 'advisory_action.dart';
import 'advisory_delivery.dart';
import 'alarms.dart';

/// Carries out the countermeasures the user accepted from a pre-warning
/// notification. Runs in the service isolate on the watchdog tick, because the
/// action-tap isolate that took the tap has neither storage nor a radio.
///
/// **Every outcome is reported back as a notification, including the failures.**
/// The user tapped a button on a locked phone and will see nothing else; a tap
/// that produced no insulin must never look like one that did, and an exception
/// in here must not be the difference between "it worked" and silence.
class AdvisoryActionRunner {
  const AdvisoryActionRunner(this._alarms);

  final G7AlarmManager _alarms;

  /// Apply everything buffered since the last tick. Cheap (one existence check)
  /// when nothing was tapped.
  ///
  /// A lapsed offer ([AdvisoryRequest.isStale]) is refused and SAID so. The
  /// user pressed a button on a locked phone and will see nothing else, so a
  /// tap that produced no insulin must never look like one that did — the same
  /// rule the failure paths below follow.
  /// Returns whether anything was applied, so the caller can tell the UI to
  /// re-read — a delivery the app knows nothing about is one the user would
  /// only learn of from a notification they may never see.
  Future<bool> run() async {
    var applied = false;
    for (final request in await const AdvisoryActionStore().drain()) {
      applied = true;
      if (request.isStale) {
        await _alarms.notifyAdvisoryOutcome('alarm.advisory.expired', const []);
        continue;
      }
      await _apply(request);
    }
    return applied;
  }

  /// One request, with anything it throws turned into a message rather than an
  /// unhandled error in an unawaited future.
  Future<void> _apply(AdvisoryRequest request) async {
    try {
      if (request.isBolus) {
        await _deliverBolus(request);
      } else {
        await _logCarbs(request);
      }
    } catch (error) {
      debugPrint('advisory action failed: $error');
      await _alarms.notifyAdvisoryOutcome('alarm.advisory.failed', const []);
    }
  }

  /// Log the rescue carbs the user said they ate. No insulin, so nothing here
  /// can suppress a later dose.
  Future<void> _logCarbs(AdvisoryRequest request) async {
    await _logMeal(request, carbs: request.amount, bolus: 0, byPump: false);
    await _alarms.notifyAdvisoryOutcome('alarm.advisory.carbs_logged', [
      request.amount.round(),
    ]);
  }

  /// Send the suggested correction to the pod and log what the pod confirmed.
  ///
  /// Only ever a PUMP dose. With no pod paired [BolusDelivery] reports
  /// `loggedOnly`, which would write insulin nobody injected into the log and
  /// suppress the next correction through insulin on board, so that case is
  /// refused outright instead. The notification offers this action only while a
  /// pod is paired; this guard covers a pod deactivated in between.
  Future<void> _deliverBolus(AdvisoryRequest request) async {
    final store = await PodStore.open();
    if (!store.hasPod) {
      await _alarms.notifyAdvisoryOutcome(
        'alarm.advisory.bolus_failed',
        const [],
      );
      return;
    }
    final delivery = await _deliveryFor(store);
    final outcome = await delivery.deliver(
      request.amount,
      deliveredLastHour: store.bolusUnitsWithin(const Duration(hours: 1)),
    );
    if (outcome.recordedUnits <= 0) {
      await _alarms.notifyAdvisoryOutcome(
        'alarm.advisory.bolus_failed',
        const [],
      );
      return;
    }
    await _logMeal(
      request,
      carbs: 0,
      bolus: outcome.recordedUnits,
      byPump: true,
    );
    await const AdvisoryDeliveryStore().record(outcome.recordedUnits);
    await _alarms.notifyAdvisoryOutcome('alarm.advisory.bolus_done', [
      outcome.recordedUnits.toStringAsFixed(2),
    ]);
  }

  /// The delivery path, wired to the SERVICE lease so it cannot connect while
  /// the pod poll or the automation holds the link, and capped by the same
  /// [ProfileBolusState] ceilings the injection sheet enforces.
  Future<BolusDelivery> _deliveryFor(PodStore store) async {
    final bolus = await ProfileBolusState.load();
    return BolusDelivery(
      controller: PodController(
        store: store,
        connection: PodConnection(store: store, lease: PodMonitor.serviceLease),
      ),
      maxBolusUnits: bolus.maxBolus.toDouble(),
      maxUnitsPerHour: bolus.maxBolus.toDouble(),
    );
  }

  /// Append to the meal log the same way the injection sheet does, then push it
  /// so the entry survives the next pull (which replaces the local log with the
  /// account's). The UI re-reads the log on its next resume, so what the service
  /// wrote here is what the app shows.
  Future<void> _logMeal(
    AdvisoryRequest request, {
    required double carbs,
    required double bolus,
    required bool byPump,
  }) async {
    const store = MealStore();
    final meals = await store.loadMeals();
    meals.add(
      Meal(
        time: DateTime.now(),
        carbs: carbs,
        glucoseMgdl: request.glucoseMgdl,
        bolus: bolus,
        entries: const [],
        deliveredByPump: byPump,
      ),
    );
    await store.saveMeals(meals);
    NutritionSync().pushMeals();
  }
}
