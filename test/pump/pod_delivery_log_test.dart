import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_running_bolus.dart';
import 'package:insulink/src/pump/pod_store.dart';

import 'fake_secure_storage.dart';

void main() {
  late Map<String, String> backing;
  late PodStore store;

  setUp(() {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  PodDelivery bolus(double units, DateTime at) =>
      PodDelivery(at: at, units: units, kind: PodDeliveryKind.bolus);

  group('the pod keeps a log of what it delivered', () {
    test('entries come back newest first', () async {
      await store.recordDelivery(bolus(1.0, DateTime(2026, 3, 1, 8)));
      await store.recordDelivery(bolus(2.0, DateTime(2026, 3, 1, 9)));

      expect(store.deliveryLog.map((entry) => entry.units), [2.0, 1.0]);
    });

    test('an entry survives a round trip through storage', () async {
      await store.recordDelivery(PodDelivery(
        at: DateTime(2026, 3, 1, 8, 30),
        units: 2.6,
        kind: PodDeliveryKind.prime,
      ));

      final restored = store.deliveryLog.single;
      expect(restored.units, 2.6);
      expect(restored.kind, PodDeliveryKind.prime);
      expect(restored.at, DateTime(2026, 3, 1, 8, 30));
    });

    /// Secure storage is not a database. The list is bounded so a long-running
    /// pod cannot grow it without limit.
    test('the oldest entries are dropped past the cap', () async {
      for (var index = 0; index < PodDeliveryLog.maxEntries + 5; index++) {
        await store.recordDelivery(
          bolus(index.toDouble(), DateTime(2026, 3, 1).add(Duration(minutes: index))),
        );
      }

      expect(store.deliveryLog, hasLength(PodDeliveryLog.maxEntries));
      expect(store.deliveryLog.first.units, (PodDeliveryLog.maxEntries + 4).toDouble());
    });

    test('an empty log reads as empty, not as a failure', () {
      expect(store.deliveryLog, isEmpty);
    });

    /// Priming and cannula insulin leaves the reservoir but never reaches the
    /// user, so counting it against a dose limit would refuse insulin they are
    /// owed.
    test('only boluses count towards the recent-insulin total', () async {
      final now = DateTime(2026, 3, 1, 12);
      await store.recordDelivery(bolus(3.0, now.subtract(const Duration(minutes: 10))));
      await store.recordDelivery(PodDelivery(
        at: now.subtract(const Duration(minutes: 20)),
        units: 2.6,
        kind: PodDeliveryKind.prime,
      ));
      await store.recordDelivery(bolus(5.0, now.subtract(const Duration(hours: 3))));

      expect(
        store.bolusUnitsWithin(const Duration(hours: 1), now: now),
        closeTo(3.0, 1e-9),
      );
    });

    test('forgetting a pod clears its log with it', () async {
      await store.recordDelivery(bolus(1.0, DateTime(2026, 3, 1, 8)));
      await store.forgetPod();
      expect(store.deliveryLog, isEmpty);
    });
  });

  group('a bolus stopped part-way is corrected, not left overstated', () {
    /// The entry was written for the full programmed dose the moment the pod
    /// took it. Leaving it there would credit the user with insulin they never
    /// received, which is the direction that suppresses a correction they need.
    test('amending replaces the units and keeps everything else', () async {
      final at = DateTime(2026, 3, 1, 12);
      await store.recordDelivery(bolus(4.0, at));

      await store.amendDelivery(at, 1.25);

      final entry = store.deliveryLog.single;
      expect(entry.units, closeTo(1.25, 1e-9));
      expect(entry.at, at);
      expect(entry.kind, PodDeliveryKind.bolus);
    });

    test('other entries are untouched', () async {
      final first = DateTime(2026, 3, 1, 11);
      final second = DateTime(2026, 3, 1, 12);
      await store.recordDelivery(bolus(2.0, first));
      await store.recordDelivery(bolus(4.0, second));

      await store.amendDelivery(second, 1.0);

      expect(store.deliveryLog.map((entry) => entry.units), [1.0, 2.0]);
    });

    test('a running bolus is remembered and cleared again', () async {
      await store.startRunningBolus(PodRunningBolus(
        startedAt: DateTime(2026, 3, 1, 12),
        pulses: 80,
        eighthSecondsBetweenPulses: 16,
      ));
      expect(store.runningBolus?.pulses, 80);

      await store.clearRunningBolus();
      expect(store.runningBolus, isNull);
    });

    test('forgetting a pod drops a bolus it was mid-way through', () async {
      await store.startRunningBolus(PodRunningBolus(
        startedAt: DateTime(2026, 3, 1, 12),
        pulses: 80,
        eighthSecondsBetweenPulses: 16,
      ));
      await store.forgetPod();
      expect(store.runningBolus, isNull);
    });
  });

  group('a bolus request is recorded before it is sent', () {
    /// Written BEFORE the command goes out, so a process that dies mid-send
    /// leaves a trace. Without it the app restarts with no idea that a dose may
    /// be running, which is the one thing it must never be unaware of.
    test('the pending request survives being read back', () async {
      await store.startPendingBolus(PodRunningBolus(
        startedAt: DateTime(2026, 3, 1, 12),
        pulses: 80,
        eighthSecondsBetweenPulses: 16,
      ));

      expect(store.pendingBolus?.programmedUnits, closeTo(4.0, 1e-9));
    });

    test('it is cleared once the pod has answered', () async {
      await store.startPendingBolus(PodRunningBolus(
        startedAt: DateTime(2026, 3, 1, 12),
        pulses: 80,
        eighthSecondsBetweenPulses: 16,
      ));
      await store.clearPendingBolus();

      expect(store.pendingBolus, isNull);
    });

    test('forgetting a pod drops a request it never answered', () async {
      await store.startPendingBolus(PodRunningBolus(
        startedAt: DateTime(2026, 3, 1, 12),
        pulses: 80,
        eighthSecondsBetweenPulses: 16,
      ));
      await store.forgetPod();

      expect(store.pendingBolus, isNull);
    });
  });
}
