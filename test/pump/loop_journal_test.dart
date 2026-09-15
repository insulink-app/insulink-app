import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/pod_store.dart';

import 'fake_secure_storage.dart';

void main() {
  late Map<String, String> backing;
  late PodStore store;
  final now = DateTime(2026, 5, 4, 12, 0);

  setUp(() {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  Future<void> cycleAt(
    DateTime at, {
    required double rate,
    double schedule = 1.0,
    bool delivered = true,
  }) {
    return store.recordLoopCycle(PodLoopCycle(
      at: at,
      unitsPerHour: rate,
      scheduledUnitsPerHour: schedule,
      reason: LoopReason.correcting,
      delivered: delivered,
    ));
  }

  group('the switch stays where it was put', () {
    test('the automation starts off', () {
      expect(store.loopMode, PodLoopMode.off);
    });

    test('a mode survives a reload', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      await store.reload();

      expect(store.loopMode, PodLoopMode.engaged);
    });

    /// The user has to be told what happened, not left to find the switch off.
    test('stopping records the cause and turns the mode off', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      await store.stopLoop(PodLoopStop.podUnreachable);

      expect(store.loopMode, PodLoopMode.off);
      expect(store.loopStop, PodLoopStop.podUnreachable);
    });

    /// The switch is the user's, so a pod change keeps it and the automation
    /// carries on with the next pod. The cycles describe the old pod and go.
    test('forgetting the pod keeps the switch but drops its cycles', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      await cycleAt(now, rate: 2.0);
      await store.forgetPod();

      expect(store.loopMode, PodLoopMode.engaged);
      expect(store.loopCycles, isEmpty);
    });
  });

  group('a cycle is billed for the time it actually ran', () {
    /// A cycle programs half an hour but is replaced after five minutes. Billing
    /// it for the half hour would overstate it roughly sixfold, and that number
    /// feeds straight back into the next decision as insulin on board.
    test('a replaced cycle is billed to its replacement, not its fuse', () async {
      await cycleAt(now.subtract(const Duration(minutes: 10)), rate: 3.0);
      await cycleAt(now.subtract(const Duration(minutes: 5)), rate: 1.0);

      final units = store.automatedUnitsWithin(
        const Duration(hours: 1),
        now: now,
      );

      expect(units, closeTo(2.0 * 5 / 60, 1e-9));
    });

    test('the newest cycle is billed up to now', () async {
      await cycleAt(now.subtract(const Duration(minutes: 6)), rate: 3.0);

      final units = store.automatedUnitsWithin(
        const Duration(hours: 1),
        now: now,
      );

      expect(units, closeTo(2.0 * 6 / 60, 1e-9));
    });

    /// A cycle nothing replaced stops counting when the pod stopped honouring
    /// it. Past the fuse the pod is on its schedule, so billing further would
    /// claim insulin the pod did not give.
    test('an abandoned cycle is billed only to the end of its fuse', () async {
      await cycleAt(now.subtract(const Duration(hours: 3)), rate: 3.0);

      final units = store.automatedUnitsWithin(
        const Duration(hours: 4),
        now: now,
      );

      expect(units, closeTo(2.0 * LoopLimits.fuse.inMinutes / 60, 1e-9));
    });

    test('only the excess above the schedule counts', () async {
      await cycleAt(now.subtract(const Duration(minutes: 30)),
          rate: 1.0, schedule: 1.0);

      expect(store.automatedUnitsWithin(const Duration(hours: 1), now: now), 0);
    });

    /// A rate below schedule withholds background insulin. That is not negative
    /// insulin in the body, and counting it as such would enlarge the next
    /// cycle's allowance on the strength of a dose nobody gave.
    test('a rate below the schedule never counts as negative insulin', () async {
      await cycleAt(now.subtract(const Duration(minutes: 30)),
          rate: 0, schedule: 2.0);

      expect(store.automatedUnitsWithin(const Duration(hours: 1), now: now), 0);
    });

    test('a cycle that was never sent is not billed', () async {
      await cycleAt(now.subtract(const Duration(minutes: 30)),
          rate: 3.0, delivered: false);

      expect(store.automatedUnitsWithin(const Duration(hours: 1), now: now), 0);
    });

    test('cycles outside the window are left out', () async {
      await cycleAt(now.subtract(const Duration(hours: 5)), rate: 3.0);

      expect(store.automatedUnitsWithin(const Duration(hours: 1), now: now), 0);
    });
  });

  group('the automation sees its own insulin', () {
    const duration = Duration(hours: 3);

    test('nothing delivered is nothing on board', () {
      expect(store.loopIobUnits(duration, now: now), 0);
    });

    /// Without this the loop is blind to what it has already given: every cycle
    /// would see only the meals and correct on top of its own corrections.
    test('a recent excess shows up on board', () async {
      await cycleAt(now.subtract(const Duration(minutes: 6)), rate: 3.0);

      final iob = store.loopIobUnits(duration, now: now);

      expect(iob, greaterThan(0.15));
      expect(iob, lessThan(0.2));
    });

    test('it decays away over the insulin duration', () async {
      await cycleAt(now.subtract(const Duration(hours: 4)), rate: 3.0);

      expect(store.loopIobUnits(duration, now: now), 0);
    });

    test('a half-spent dose is about half on board', () async {
      await cycleAt(now.subtract(const Duration(minutes: 95)), rate: 3.0);
      await cycleAt(now.subtract(const Duration(minutes: 90)), rate: 1.0);

      final delivered = 2.0 * 5 / 60;
      final iob = store.loopIobUnits(duration, now: now);

      expect(iob, closeTo(delivered * 0.5, delivered * 0.05));
    });
  });

  group('a dose nobody could confirm counts as given', () {
    const duration = Duration(hours: 3);

    Future<void> unconfirmed(DateTime at, double units) =>
        store.recordUnconfirmedBolus(
          PodDelivery(at: at, units: units, kind: PodDeliveryKind.bolus),
        );

    /// The user's calculator deliberately records nothing for these, so it can
    /// never suppress a correction they need. The automation cannot look at the
    /// pod to find out, so it has to assume the worst instead.
    test('it shows up as insulin on board', () async {
      await unconfirmed(now.subtract(const Duration(minutes: 90)), 6.0);

      expect(store.unconfirmedBolusUnits(duration, now: now), closeTo(3.0, 1e-9));
    });

    test('it decays away like any other dose', () async {
      await unconfirmed(now.subtract(const Duration(hours: 4)), 6.0);

      expect(store.unconfirmedBolusUnits(duration, now: now), 0);
    });

    test('nothing recorded is nothing assumed', () {
      expect(store.unconfirmedBolusUnits(duration, now: now), 0);
    });

    test('entries too old for any insulin model are dropped', () async {
      await unconfirmed(now.subtract(const Duration(hours: 30)), 6.0);
      await unconfirmed(now, 2.0);

      expect(store.unconfirmedBoluses, hasLength(1));
      expect(store.unconfirmedBoluses.single.units, 2.0);
    });

    test('forgetting the pod forgets them', () async {
      await unconfirmed(now, 6.0);
      await store.forgetPod();

      expect(store.unconfirmedBoluses, isEmpty);
    });
  });

  test('the journal is capped so a long pod life cannot grow it forever',
      () async {
    for (var index = 0; index < PodLoopJournal.maxCycles + 20; index++) {
      await cycleAt(now.subtract(Duration(minutes: index)), rate: 2.0);
    }

    expect(store.loopCycles, hasLength(PodLoopJournal.maxCycles));
  });
}
