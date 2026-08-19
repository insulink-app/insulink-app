import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_store.dart';

import 'fake_secure_storage.dart';

void main() {
  late Map<String, String> backing;
  late PodStore store;

  setUp(() {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  group('the basal schedule the pod is running', () {
    test('round-trips 24 hourly rates', () async {
      final rates = [for (var hour = 0; hour < 24; hour++) hour * 0.05];
      await store.saveBasalRates(rates);
      expect(store.basalRates, rates);
    });

    test('a schedule of the wrong length is refused on read', () async {
      await store.saveBasalRates([1.0, 2.0]);
      expect(store.basalRates, isNull);
    });

    test('no schedule reads as none', () {
      expect(store.basalRates, isNull);
    });
  });

  group('the delivery ledger never double-counts and never gaps', () {
    test('the mark starts where accounting was opened', () async {
      final opened = DateTime(2026, 3, 1, 12, 0);
      await store.startBasalAccounting(opened);
      expect(store.basalCountedTo, opened);
      expect(store.pendingBasalDeliveries, isEmpty);
    });

    test('recording a window moves the mark to its end', () async {
      final opened = DateTime(2026, 3, 1, 12, 0);
      final closed = DateTime(2026, 3, 1, 12, 15);
      await store.startBasalAccounting(opened);
      await store.addBasalDelivery(at: closed, units: 0.25, countedTo: closed);

      expect(store.basalCountedTo, closed);
      expect(store.pendingBasalDeliveries, hasLength(1));
      expect(store.pendingBasalDeliveries.single['units'], 0.25);
      expect(
        store.pendingBasalDeliveries.single['at'],
        closed.millisecondsSinceEpoch,
      );
    });

    /// A window that delivered nothing still has to close, or the next poll would
    /// bill the whole stretch as if the pod had been running through it.
    test('a zero window closes the mark without recording insulin', () async {
      final opened = DateTime(2026, 3, 1, 12, 0);
      final closed = DateTime(2026, 3, 1, 12, 15);
      await store.startBasalAccounting(opened);
      await store.addBasalDelivery(at: closed, units: 0, countedTo: closed);

      expect(store.basalCountedTo, closed);
      expect(store.pendingBasalDeliveries, isEmpty);
    });

    test('successive windows accumulate in order', () async {
      final start = DateTime(2026, 3, 1, 12, 0);
      await store.startBasalAccounting(start);
      for (var step = 1; step <= 3; step++) {
        final end = start.add(Duration(minutes: 15 * step));
        await store.addBasalDelivery(at: end, units: 0.2, countedTo: end);
      }
      expect(store.pendingBasalDeliveries, hasLength(3));
      expect(store.basalCountedTo, start.add(const Duration(minutes: 45)));
    });
  });

  group('the pending queue', () {
    Future<void> fill(int count) async {
      final start = DateTime(2026, 3, 1, 12, 0);
      for (var step = 1; step <= count; step++) {
        final end = start.add(Duration(minutes: 15 * step));
        await store.addBasalDelivery(at: end, units: 0.2, countedTo: end);
      }
    }

    test('accepted samples are dropped from the front', () async {
      await fill(5);
      await store.clearBasalDeliveries(3);
      expect(store.pendingBasalDeliveries, hasLength(2));
    });

    test('clearing everything empties it', () async {
      await fill(3);
      await store.clearBasalDeliveries(3);
      expect(store.pendingBasalDeliveries, isEmpty);
    });

    /// An unbounded queue in secure storage is its own problem, and insulin that
    /// old is no longer shaping a forecast.
    test('it is capped, dropping the oldest', () async {
      await fill(210);
      final pending = store.pendingBasalDeliveries;
      expect(pending, hasLength(200));
      // The newest sample survived; the oldest did not.
      expect(
        pending.last['at'],
        DateTime(2026, 3, 1, 12, 0)
            .add(const Duration(minutes: 15 * 210))
            .millisecondsSinceEpoch,
      );
    });

    test('forgetting the pod clears the ledger too', () async {
      await store.saveBasalRates(List<double>.filled(24, 1.0));
      await fill(3);
      await store.forgetPod();
      expect(store.basalRates, isNull);
      expect(store.pendingBasalDeliveries, isEmpty);
      expect(store.basalCountedTo, isNull);
    });
  });

  group('the basal total is what the user is shown', () {
    /// Kept apart from the pending queue, which is emptied the moment the account
    /// accepts it. A total that vanished on every successful sync would be no use
    /// on a log page.
    test('it survives the queue being drained', () async {
      await store.addBasalDelivery(
        at: DateTime(2026, 3, 1, 9),
        units: 0.25,
        countedTo: DateTime(2026, 3, 1, 9),
      );
      await store.addBasalDelivery(
        at: DateTime(2026, 3, 1, 9, 15),
        units: 0.25,
        countedTo: DateTime(2026, 3, 1, 9, 15),
      );

      await store.clearBasalDeliveries(2);

      expect(store.pendingBasalDeliveries, isEmpty);
      expect(store.basalDeliveredTotal, closeTo(0.5, 1e-9));
    });

    /// A window the pod spent suspended is booked as nothing, and the total has
    /// to reflect that rather than the schedule it did not run.
    test('a window that delivered nothing adds nothing', () async {
      await store.addBasalDelivery(
        at: DateTime(2026, 3, 1, 9),
        units: 0,
        countedTo: DateTime(2026, 3, 1, 9),
      );

      expect(store.basalDeliveredTotal, 0);
    });

    test('a fresh pod starts at zero', () async {
      await store.addBasalDelivery(
        at: DateTime(2026, 3, 1, 9),
        units: 1.5,
        countedTo: DateTime(2026, 3, 1, 9),
      );
      await store.forgetPod();

      expect(store.basalDeliveredTotal, 0);
    });
  });
}
