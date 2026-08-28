import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_log_entry.dart';
import 'package:insulink/src/pump/pod_store.dart';

import 'fake_secure_storage.dart';

void main() {
  late Map<String, String> backing;
  late PodStore store;

  setUp(() {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  Future<void> bookBasal(DateTime at, double units) => store.addBasalDelivery(
        at: at,
        units: units,
        countedTo: at,
      );

  group('basal is kept per hour, not per booking', () {
    /// The watch books every quarter of an hour. Keeping each one would make a
    /// pod's life three hundred rows of nothing anyone reads.
    test('four quarter-hour bookings become one hour', () async {
      final hour = DateTime(2026, 3, 1, 13);
      for (var quarter = 0; quarter < 4; quarter++) {
        await bookBasal(hour.add(Duration(minutes: 15 * quarter)), 0.2);
      }

      expect(store.basalHours, hasLength(1));
      expect(store.basalHours.single.hour, hour);
      expect(store.basalHours.single.units, closeTo(0.8, 1e-9));
    });

    test('a new hour starts its own row', () async {
      await bookBasal(DateTime(2026, 3, 1, 13, 45), 0.2);
      await bookBasal(DateTime(2026, 3, 1, 14, 0), 0.2);

      expect(store.basalHours.map((entry) => entry.hour.hour), [13, 14]);
    });

    /// A window the pod spent suspended is booked as nothing, and no row should
    /// appear claiming otherwise.
    test('an hour that delivered nothing gets no row', () async {
      await bookBasal(DateTime(2026, 3, 1, 13), 0);

      expect(store.basalHours, isEmpty);
    });

    /// It used to be cleared with the pod, which emptied the insulin chart's
    /// basal bars the moment a dead pod was let go of. What went into the user
    /// last Tuesday did not stop having happened because the pod that delivered
    /// it was discarded, so the ledger outlives it and only its own cap ages it
    /// out. The pod-scoped RUNNING TOTAL is what still goes.
    test('forgetting a pod keeps the basal history it recorded', () async {
      await bookBasal(DateTime(2026, 3, 1, 13), 0.8);
      await store.forgetPod();

      expect(store.basalHours, hasLength(1));
      expect(store.basalDeliveredTotal, 0);
    });
  });

  group('the history reads as one timeline', () {
    /// Doses and basal live apart in storage, for good reason, and are only
    /// brought together for reading.
    test('doses and basal are interleaved, newest first', () async {
      await store.recordDelivery(PodDelivery(
        at: DateTime(2026, 3, 1, 13, 30),
        units: 4.0,
        kind: PodDeliveryKind.bolus,
      ));
      await bookBasal(DateTime(2026, 3, 1, 13, 15), 0.8);
      await bookBasal(DateTime(2026, 3, 1, 14, 15), 0.8);

      final timeline = PodLogEntry.timeline(store);

      expect(timeline.map((entry) => entry.at), [
        DateTime(2026, 3, 1, 14),
        DateTime(2026, 3, 1, 13, 30),
        DateTime(2026, 3, 1, 13),
      ]);
    });

    /// Only a bolus is insulin the user chose. Priming, cannula and basal are
    /// toned apart so the list cannot be read as a list of doses.
    test('only a bolus counts as a dose', () async {
      await store.recordDelivery(PodDelivery(
        at: DateTime(2026, 3, 1, 12),
        units: 2.6,
        kind: PodDeliveryKind.prime,
      ));
      await store.recordDelivery(PodDelivery(
        at: DateTime(2026, 3, 1, 13),
        units: 4.0,
        kind: PodDeliveryKind.bolus,
      ));
      await bookBasal(DateTime(2026, 3, 1, 14), 0.8);

      final byLabel = {
        for (final entry in PodLogEntry.timeline(store))
          entry.labelKey: entry.isDose,
      };

      expect(byLabel['pump.log.kind.bolus'], isTrue);
      expect(byLabel['pump.log.kind.prime'], isFalse);
      expect(byLabel['pump.log.kind.basal'], isFalse);
    });

    test('an hour of basal is marked as spanning one', () async {
      await bookBasal(DateTime(2026, 3, 1, 13, 15), 0.8);

      expect(PodLogEntry.timeline(store).single.spansAnHour, isTrue);
    });
  });
}
