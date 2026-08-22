import 'package:flutter/foundation.dart';
import 'package:insulink/src/injection/bolus_delivery.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';

/// Carries a bolus to the pod after the sheet that asked for it has closed.
///
/// The pod takes a few seconds to answer and minutes to deliver, and holding a
/// modal open for that is the wrong trade: the user has confirmed, and what they
/// want next is their overview, not a spinner. So the sheet hands the dose over
/// here and pops, and the overview shows what became of it.
///
/// Lives above the page tree for exactly that reason — it has to outlive the page
/// that started the delivery.
///
/// The meal is written BEFORE the pod answers, carrying its carbs and no insulin.
/// Carbs are certain, insulin is not, and that ordering means a process that dies
/// mid-delivery loses neither: the carbs are already logged, and the dose is
/// recorded only once the pod has named it back.
class BolusDispatcher extends ChangeNotifier {
  BolusDispatcher({required this.controller, required this.meals});

  final PodController controller;
  final MealState meals;

  BolusDeliveryResult? _outcome;
  bool _inFlight = false;

  /// Whether a dose is on its way to the pod and has not been answered yet.
  ///
  /// Read from the store as well as from memory, so a bolus left in flight by a
  /// process that died still reads as pending after a restart.
  bool get isSending => _inFlight || controller.store.pendingBolus != null;

  /// Units of the dose currently on its way, or null when none is.
  double? get sendingUnits =>
      _inFlight || controller.store.pendingBolus != null
          ? controller.store.pendingBolus?.programmedUnits
          : null;

  /// The last outcome worth showing: a refusal or an unknown result. Sticky until
  /// dismissed, because it means the meal on file has no insulin against it.
  BolusDeliveryResult? get failure =>
      _outcome != null && _outcome!.needsAttention ? _outcome : null;

  void dismissFailure() {
    _outcome = null;
    notifyListeners();
  }

  /// Sends [units] and, once the pod confirms, writes them onto [meal].
  ///
  /// Deliberately not awaited by the caller: the page is free to close the moment
  /// this returns. The future is held only so the outcome can be applied.
  void submit({
    required BolusDelivery delivery,
    required double units,
    required double deliveredLastHour,
    required Meal meal,
  }) {
    if (_inFlight) {
      return;
    }
    _inFlight = true;
    _outcome = null;
    notifyListeners();
    _run(delivery, units, deliveredLastHour, meal);
  }

  Future<void> _run(
    BolusDelivery delivery,
    double units,
    double deliveredLastHour,
    Meal meal,
  ) async {
    try {
      final outcome = await delivery.deliver(
        units,
        deliveredLastHour: deliveredLastHour,
      );
      _outcome = outcome;
      if (outcome.recordedUnits > 0) {
        await meals.updateMeal(meal, meal.copyWith(bolus: outcome.recordedUnits));
      }
    } catch (error) {
      // Catch-all: an escaping Error would leave this stuck on "sending" with no
      // way for the user to find out what happened. The command may already have
      // reached the pod, so the dose is noted as possibly given, exactly as the
      // delivery path does for an outcome it cannot confirm.
      await _noteUnconfirmed(units);
      _outcome = BolusDeliveryResult.unknown('$error');
    } finally {
      _inFlight = false;
      notifyListeners();
    }
  }

  /// Resolves a dose the app was still sending when it was killed.
  ///
  /// Reads the pod: a bolus it reports running is adopted as exactly that, and
  /// anything else is reported as unknown rather than guessed. Under no
  /// circumstance is the dose written onto a meal here — the app cannot tell how
  /// much of it went in, and inventing the number is the one mistake that would
  /// suppress a correction the user needs.
  /// Records a dose nobody could confirm, so the insulin-on-board every dose
  /// calculation subtracts includes the possibility that it went in.
  Future<void> _noteUnconfirmed(double units) async {
    if (units <= 0) {
      return;
    }
    await controller.store.recordUnconfirmedBolus(PodDelivery(
      at: DateTime.now(),
      units: units,
      kind: PodDeliveryKind.bolus,
    ));
  }

  Future<void> resolveStranded() async {
    final pending = controller.store.pendingBolus;
    if (pending == null || _inFlight) {
      return;
    }
    await controller.store.clearPendingBolus();
    await controller.refreshIfStale();
    final status = controller.status;
    if (status != null &&
        (status.delivery.isBolusing || status.bolusPulsesRemaining > 0)) {
      await controller.store.startRunningBolus(pending);
      _outcome = null;
    } else {
      // The pod is not reporting a bolus, which does NOT mean none was given: a
      // dose sent before the app died has had until now to finish, and a
      // finished bolus leaves the pod looking idle. So it is noted as possibly
      // delivered rather than assumed away.
      await _noteUnconfirmed(pending.programmedUnits);
      _outcome = BolusDeliveryResult.unknown(
        'The app was closed while a bolus was being sent',
      );
    }
    notifyListeners();
  }
}
