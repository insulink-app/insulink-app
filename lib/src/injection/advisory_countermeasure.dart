import 'package:flutter/widgets.dart';
import 'package:insulink/src/cgm/service/advisory_action.dart';
import 'package:insulink/src/injection/bolus_delivery.dart';
import 'package:insulink/src/injection/bolus_dispatcher.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:provider/provider.dart';

/// Carries out a countermeasure the user accepted from a pre-warning
/// notification, through exactly the paths the injection sheet uses.
///
/// Runs in the UI isolate, which is the point: the meal reaches [MealState] so
/// the log on screen is the log on disk, and the dose goes through
/// [BolusDispatcher], which already reports what became of it. Written into the
/// background service instead, the meal was invisible to the running app and
/// would have been overwritten by the next one logged in it.
class AdvisoryCountermeasure {
  const AdvisoryCountermeasure(this.context);

  final BuildContext context;

  Future<void> run(AdvisoryRequest request) {
    return request.isBolus ? _deliverBolus(request) : _logCarbs(request);
  }

  /// Log the rescue carbs the user said they ate. No insulin, so nothing here
  /// can suppress a later dose.
  Future<void> _logCarbs(AdvisoryRequest request) {
    return context.read<MealState>().addMeal(
      _meal(request, carbs: request.amount, byPump: false),
    );
  }

  /// Send the suggested correction to the pod.
  ///
  /// Only ever a PUMP dose. With no pod paired [BolusDelivery] reports
  /// `loggedOnly`, which would write insulin nobody injected into the log and
  /// suppress the next correction through insulin on board, so that case is
  /// dropped instead. The notification offers this button only while a pod is
  /// paired; this covers a pod deactivated in between.
  ///
  /// The store is re-read first: its getters come from a cache that is per
  /// isolate, and the background service books delivery into it, so the rolling
  /// hourly limit would otherwise be checked against a stale total.
  Future<void> _deliverBolus(AdvisoryRequest request) async {
    final pod = context.read<PodController>();
    await pod.store.reload();
    if (!pod.hasPod || !context.mounted) {
      return;
    }
    final meal = _meal(request, carbs: 0, byPump: true);
    await context.read<MealState>().addMeal(meal);
    if (!context.mounted) {
      return;
    }
    final maxUnits = context.read<ProfileBolusState>().maxBolus.toDouble();
    context.read<BolusDispatcher>().submit(
      delivery: BolusDelivery(
        controller: pod,
        maxBolusUnits: maxUnits,
        maxUnitsPerHour: maxUnits,
      ),
      units: request.amount,
      deliveredLastHour: pod.store.bolusUnitsWithin(const Duration(hours: 1)),
      meal: meal,
    );
  }

  /// The meal the countermeasure is logged against. Insulin is left at zero even
  /// for a bolus: the dispatcher writes it on once the pod has named it back,
  /// exactly as the injection sheet does, so a dose that never ran is never in
  /// the log.
  Meal _meal(
    AdvisoryRequest request, {
    required double carbs,
    required bool byPump,
  }) {
    return Meal(
      time: DateTime.now(),
      carbs: carbs,
      glucoseMgdl: request.glucoseMgdl,
      bolus: 0,
      entries: const [],
      deliveredByPump: byPump,
    );
  }
}
