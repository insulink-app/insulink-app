import 'dart:typed_data';

import 'package:insulink/src/demo/demo_loop.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:insulink/src/pump/pod_basal_adapter.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';

/// An Omnipod DASH the demo treats as paired and running for almost two days,
/// so the pump page shows a live pod with automated delivery on, and the glucose
/// chart has basal bars.
///
/// Only the store is filled, through the same calls activation and the hourly
/// basal booking use; the in-memory demo pod (`demo_pod.dart`) answers every
/// status request with a running pod. The key is zeros: nothing is ever
/// encrypted, because there is no radio.
class DemoPump {
  DemoPump(this.now, this.readings);

  final DateTime now;

  /// The demo glucose, which the automation decides on.
  final Map<DateTime, int> readings;

  static const Duration age = Duration(hours: 46);
  static const int uniqueId = 4242;
  static const int deliveredPulses = 1640;
  static const int reservoirPulses = 770;

  /// Units per hour from midnight, with the usual early-morning rise.
  static const List<double> hourlyRates = [
    0.35,
    0.35,
    0.35,
    0.45,
    0.5,
    0.55,
    0.55,
    0.5,
    0.45,
    0.4,
    0.4,
    0.4,
    0.4,
    0.4,
    0.4,
    0.4,
    0.4,
    0.45,
    0.45,
    0.4,
    0.4,
    0.35,
    0.35,
    0.35,
  ];

  Future<void> attach() async {
    final store = await PodStore.open();
    final activatedAt = now.subtract(age);
    await store.savePairing(
      uniqueId: uniqueId,
      longTermKey: Uint8List(16),
      lotNumber: 135556289,
      podSequenceNumber: 681767,
      activatedAt: activatedAt,
      expiryHours: 80,
      resetSessionCounters: true,
    );
    await store.saveActivationStep('running');
    final rates = await _adoptProfile();
    await store.saveBasalRates(rates);
    await _bookBasal(store, activatedAt, rates);
    await _bookContacts(store);
    await DemoLoop(
      store: store,
      readings: readings,
      status: _status(PodDeliveryStatus.basalActive),
      now: now,
    ).engage();
    final automated = store.temporaryBasal?.covers(now) ?? false;
    await store.saveLastStatus(
      _status(
        automated
            ? PodDeliveryStatus.tempBasalActive
            : PodDeliveryStatus.basalActive,
      ),
      now,
    );
  }

  /// A status as the pod sends it: running with [delivery], 82 U given and
  /// 38.5 U left, so the reservoir bar has a reading to show.
  PodStatusResponse _status(PodDeliveryStatus delivery) {
    final body = Uint8List(10);
    body[0] = 0x1d;
    body[1] =
        (delivery.value << 4) |
        PodLifecycleStatus.runningAboveMinimumVolume.value;
    ByteData.view(body.buffer)
      ..setUint32(2, deliveredPulses << 15)
      ..setUint32(6, (age.inMinutes << 10) | reservoirPulses);
    return PodStatusResponse(body);
  }

  /// Makes [hourlyRates] the active basal profile and returns what the pod would
  /// be programmed with for it, so the pump page sees the pod running the
  /// profile instead of offering to send it.
  Future<List<double>> _adoptProfile() async {
    final basal = await ProfileBasalState.load();
    final profile = basal.active.copy();
    for (final (hour, rate) in hourlyRates.indexed) {
      profile.setHour(hour, rate);
    }
    profile.dailyTotal = profile.total;
    basal.updateProfile(basal.activeIndex, profile);
    return PodController.hourlyRatesOf(PodBasalAdapter(profile).program);
  }

  /// The background poll's contacts every 15 minutes over the last day, up to
  /// where the automation's own five-minute cycles take over.
  Future<void> _bookContacts(PodStore store) async {
    final until = now.subtract(DemoLoop.cycleEvery * DemoLoop.cycleCount);
    var at = now.subtract(const Duration(days: 1));
    while (at.isBefore(until)) {
      await store.markSeen(at);
      at = at.add(const Duration(minutes: 15));
    }
  }

  /// Every full hour since activation, booked the way the service books it.
  Future<void> _bookBasal(
    PodStore store,
    DateTime activatedAt,
    List<double> rates,
  ) async {
    var hour = DateTime(
      activatedAt.year,
      activatedAt.month,
      activatedAt.day,
      activatedAt.hour + 1,
    );
    while (hour.add(const Duration(hours: 1)).isBefore(now)) {
      final next = hour.add(const Duration(hours: 1));
      await store.addBasalDelivery(
        at: hour,
        units: rates[hour.hour],
        countedTo: next,
      );
      hour = next;
    }
  }
}
