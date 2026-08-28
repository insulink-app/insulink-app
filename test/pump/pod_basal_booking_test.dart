import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_basal_booking.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

import 'fake_secure_storage.dart';

/// A pod reporting that it is running its schedule, which is what a booking is
/// gated on.
PodStatusResponse delivering({
  PodDeliveryStatus delivery = PodDeliveryStatus.basalActive,
}) {
  final body = Uint8List(10);
  body[0] = 0x1d;
  body[1] = (delivery.value << 4) |
      PodLifecycleStatus.runningAboveMinimumVolume.value;
  ByteData.view(body.buffer)
    ..setUint32(2, 0)
    ..setUint32(6, 0x3FF);
  return PodStatusResponse(body);
}

void main() {
  late Map<String, String> backing;
  late PodStore store;

  setUp(() {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  List<double> flatRates(double unitsPerHour) =>
      [for (var hour = 0; hour < 24; hour++) unitsPerHour];

  group('a ledger that was never opened opens itself', () {
    /// The regression this guards: only the activation wizard opened the mark, so
    /// a pod adopted from the account and then sent the profile had a schedule on
    /// file and no mark, and booked nothing for the rest of its life. The insulin
    /// chart, the pump history and the samples the account gets were all empty.
    test('a known schedule with no mark starts accounting instead of nothing',
        () async {
      final opened = DateTime(2026, 5, 4, 9, 30);
      await store.saveBasalRates(flatRates(0.8));

      final booked =
          await PodBasalBooking(store, now: () => opened).book(delivering());

      expect(booked, isNull);
      expect(store.basalCountedTo, opened);
    });

    test('the poll after it books the window that has passed', () async {
      final opened = DateTime(2026, 5, 4, 9, 30);
      await store.saveBasalRates(flatRates(0.8));
      await PodBasalBooking(store, now: () => opened).book(delivering());

      final booked = await PodBasalBooking(
        store,
        now: () => opened.add(const Duration(minutes: 30)),
      ).book(delivering());

      expect(booked, closeTo(0.4, 1e-9));
      expect(store.basalHours.single.units, closeTo(0.4, 1e-9));
    });

    test('no schedule on file still books nothing and opens no mark', () async {
      final booked = await PodBasalBooking(store, now: DateTime.now)
          .book(delivering());

      expect(booked, isNull);
      expect(store.basalCountedTo, isNull);
    });
  });
}
