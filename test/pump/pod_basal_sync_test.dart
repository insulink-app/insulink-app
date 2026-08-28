import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';

import 'fake_secure_storage.dart';

void main() {
  late Map<String, String> backing;
  late PodStore store;
  late PodController controller;

  /// A flat schedule at [unitsPerHour], as the adapter builds one: two half-hour
  /// slots per hour, all the same.
  PodBasalProgram flat(double unitsPerHour) {
    final hundredths = (unitsPerHour * 100).round();
    return PodBasalProgram([
      for (var hour = 0; hour < 24; hour++)
        PodBasalSegment(
          startSlot: hour * 2,
          endSlot: (hour + 1) * 2,
          rateHundredthUnitsPerHour: hundredths,
        ),
    ]);
  }

  setUp(() async {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
    await store.savePairing(
      uniqueId: 4241,
      longTermKey: FakeSecureStorage.dummyKey,
      lotNumber: 1,
      podSequenceNumber: 2,
      activatedAt: DateTime.now(),
    );
    controller = PodController(store: store);
  });

  group('the pod holds its own schedule, so an edit has to be sent', () {
    /// This used to assert the opposite, reasoning that a notice about a schedule
    /// we never captured would be noise. That held only while every paired pod
    /// had been through the wizard, which saves the rates it programmed. A pod
    /// adopted from the account has not: the app holds its key and no idea what
    /// it runs. Treating that as "already matches" hid the only control that
    /// sends a schedule, while the automation refused to start for want of that
    /// same schedule, with no way out of it.
    test('a pod with no schedule on file is flagged, not assumed to match',
        () async {
      expect(controller.runsDifferentBasalThan(flat(0.8)), isTrue);
    });

    test('a profile matching what the pod was given is not flagged', () async {
      await store.saveBasalRates(PodController.hourlyRatesOf(flat(0.8)));
      expect(controller.runsDifferentBasalThan(flat(0.8)), isFalse);
    });

    /// The whole point: the app would otherwise show one schedule while the pod
    /// quietly delivered another.
    test('an edited profile is flagged as not yet on the pod', () async {
      await store.saveBasalRates(PodController.hourlyRatesOf(flat(0.8)));
      expect(controller.runsDifferentBasalThan(flat(1.2)), isTrue);
    });

    test('a difference in a single hour is enough', () async {
      final rates = PodController.hourlyRatesOf(flat(0.8));
      await store.saveBasalRates(rates);
      final edited = PodBasalProgram([
        const PodBasalSegment(
            startSlot: 0, endSlot: 2, rateHundredthUnitsPerHour: 120),
        const PodBasalSegment(
            startSlot: 2, endSlot: 48, rateHundredthUnitsPerHour: 80),
      ]);
      expect(controller.runsDifferentBasalThan(edited), isTrue);
    });

    test('the rates are sampled once per hour, inside the hour', () {
      final rates = PodController.hourlyRatesOf(flat(0.8));
      expect(rates, hasLength(24));
      expect(rates.every((rate) => (rate - 0.8).abs() < 1e-9), isTrue);
    });
  });
}
