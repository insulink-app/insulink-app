import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/pod_store.dart';

import 'fake_secure_storage.dart';

void main() {
  late PodStore store;
  final now = DateTime(2026, 5, 4, 12, 0);
  const insulinDuration = Duration(hours: 3);

  setUp(() {
    final backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  /// Without this the loop would not see its own micro boluses and would stack
  /// one on top of the next.
  test('a micro bolus counts as insulin on board and decays', () async {
    await store.bookLoopMicroBolus(1.5, now);

    expect(store.loopIobUnits(insulinDuration, now: now), closeTo(1.5, 1e-9));
    expect(
      store.loopIobUnits(
        insulinDuration,
        now: now.add(const Duration(minutes: 90)),
      ),
      closeTo(0.75, 1e-9),
    );
  });

  test('micro boluses count toward the hourly ceiling', () async {
    await store.bookLoopMicroBolus(0.5, now.subtract(const Duration(hours: 2)));
    await store.bookLoopMicroBolus(
      0.4,
      now.subtract(const Duration(minutes: 30)),
    );
    await store.bookLoopMicroBolus(
      0.3,
      now.subtract(const Duration(minutes: 5)),
    );

    final lastHour = store.automatedUnitsWithin(
      const Duration(hours: 1),
      now: now,
    );

    expect(lastHour, closeTo(0.7, 1e-9));
  });

  test('they add to the rate the automation ran above schedule', () async {
    await store.recordLoopCycle(
      PodLoopCycle(
        at: now.subtract(const Duration(minutes: 30)),
        unitsPerHour: 3,
        scheduledUnitsPerHour: 1,
        reason: LoopReason.correcting,
        delivered: true,
      ),
    );
    await store.bookLoopMicroBolus(0.5, now);

    final lastHour = store.automatedUnitsWithin(
      const Duration(hours: 1),
      now: now,
    );

    expect(lastHour, closeTo(1.0 + 0.5, 1e-9));
  });

  test('a refusal takes exactly that micro bolus back', () async {
    final earlier = now.subtract(const Duration(minutes: 5));
    await store.bookLoopMicroBolus(0.4, earlier);
    await store.bookLoopMicroBolus(0.6, now);

    await store.unbookLoopMicroBolus(now);

    expect(store.loopMicroBoluses.single.units, 0.4);
    expect(store.lastLoopMicroBolusAt, earlier);
  });

  /// A micro bolus the user stopped part-way counts only what went in.
  test('a stopped micro bolus is corrected to what was given', () async {
    await store.bookLoopMicroBolus(0.5, now);

    await store.amendLoopMicroBolus(now, 0.2);

    expect(store.loopMicroBoluses.single.units, 0.2);
  });

  test('the ledger survives a reload', () async {
    await store.bookLoopMicroBolus(0.5, now);
    await store.reload();

    expect(
      store.loopMicroBolusUnitsWithin(const Duration(hours: 1), now: now),
      0.5,
    );
  });
}
