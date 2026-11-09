import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../injection/bolus_delivery.dart';
import '../../nutrition/meal/meal_store.dart';
import '../../profile/glucose/profile_glucose_state.dart';
import '../../pump/loop/loop_glucose.dart';
import '../../pump/pod_store.dart';
import '../../pump/split_bolus.dart';
import '../../pump/split_bolus_stop.dart';
import 'advisory_action_runner.dart';
import 'alarms.dart';
import 'split_bolus_part_log.dart';

/// Gives the parts of a split bolus as they fall due. Runs in the service
/// isolate inside the pod chain (`CgmTaskHandler._tickPodChain`), so a part
/// never opens a pod session beside the poll or an automation cycle.
///
/// A part the pod is busy for (a micro bolus, the user's own bolus) waits for
/// the next tick. Any other failure, and a part that missed its time by more
/// than [SplitBolusPlan.lateAfter], ends the whole plan and SAYS so: the user
/// expects that insulin, and silence would read as if it went in.
class SplitBolusRunner {
  const SplitBolusRunner(this._alarms, {required this.readGlucose});

  final G7AlarmManager _alarms;

  /// The sensor input the automation decides on, read the same way here.
  final Future<LoopGlucose> Function() readGlucose;

  /// Refusals that only mean "not now".
  static const _busyKeys = {
    'pump.bolus.already_running',
    'pump.bolus.queue_too_long',
    BolusDelivery.linkBusy,
  };

  /// Gives the part that is due, if any. Returns whether something changed, so
  /// the caller can tell the UI to re-read.
  ///
  /// Must not run twice at once in one isolate (the pod chain guards it): a pod
  /// session can outlast the 30 s tick, and a second run would read a part
  /// still marked as sending as a send that died.
  ///
  /// Checks for a plan with a single key read first: opening the store
  /// decrypts the whole keystore, far too much for every 30 s tick when there
  /// is nothing to give, which is almost always.
  Future<bool> run() async {
    if (!await const FlutterSecureStorage().containsKey(
      key: PodStore.splitBolusKey,
    )) {
      return false;
    }
    final store = await PodStore.open();
    final plan = store.splitBolus;
    if (plan == null) {
      return false;
    }
    if (plan.sendingSince != null) {
      return _dropStranded(store, plan);
    }
    if (plan.parts.first.at.isAfter(DateTime.now())) {
      return false;
    }
    return _due(store, plan);
  }

  /// Gives the due first part, unless something stops the plan.
  Future<bool> _due(PodStore store, SplitBolusPlan plan) async {
    final glucose = await readGlucose();
    final low = (await ProfileGlucoseState.load()).low;
    final stop = SplitBolusStop(lowMgdl: low).reasonFor(
      plan,
      hasPod: store.hasPod,
      mealLogged: await _mealLogged(plan),
      glucose: glucose,
      now: DateTime.now(),
    );
    if (stop != null) {
      return _abandon(store, stop);
    }
    return _give(store, plan, glucose);
  }

  Future<bool> _mealLogged(SplitBolusPlan plan) async =>
      (await const MealStore().loadMeals()).any(
        (meal) => meal.logKey == plan.mealKey,
      );

  /// A part a dead process was sending. It may have gone in, so it is never
  /// sent again; the delivery path left its pending record for the app to
  /// resolve, and the rest of the plan carries on.
  Future<bool> _dropStranded(PodStore store, SplitBolusPlan plan) async {
    await _saveRest(store, plan);
    return true;
  }

  /// Marks the first part as sending, sends it, then settles the plan against
  /// what the store holds NOW ([_settle]).
  Future<bool> _give(
    PodStore store,
    SplitBolusPlan plan,
    LoopGlucose glucose,
  ) async {
    final mark = DateTime.now();
    await store.saveSplitBolus(plan.sendingAt(mark));
    final outcome = await _send(store, plan.parts.first);
    await store.reload();
    final current = store.splitBolus;
    final ours = current != null && current.markedAt(mark) ? current : null;
    if (outcome.recordedUnits > 0) {
      await const SplitBolusPartLog().record(outcome, plan, glucose);
    }
    return _settle(store, ours, outcome);
  }

  /// Moves the plan on after a send. [ours] is the plan as stored now if it is
  /// still the one that was sent from, else null: the user cancelled meanwhile
  /// or started a new plan, and neither is touched.
  Future<bool> _settle(
    PodStore store,
    SplitBolusPlan? ours,
    BolusDeliveryResult outcome,
  ) async {
    if (ours == null) {
      return true;
    }
    if (outcome.recordedUnits > 0) {
      await _saveRest(store, ours);
      return true;
    }
    if (_busyKeys.contains(outcome.detailKey)) {
      await store.saveSplitBolus(ours.settled);
      return false;
    }
    return _abandon(store, 'alarm.split_bolus.failed');
  }

  Future<BolusDeliveryResult> _send(PodStore store, SplitBolusPart part) async {
    final delivery = await AdvisoryActionRunner(
      _alarms,
    ).serviceDelivery(store, source: PodDeliverySource.app);
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
    await _alarms.notifyAdvisoryOutcome(
      bodyKey,
      const [],
      titleKey: 'alarm.split_bolus.title',
    );
    return true;
  }
}
