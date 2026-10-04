import 'dart:typed_data';

import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:insulink/src/pump/pod_basal_adapter.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';

/// An Omnipod DASH the demo treats as paired and running for almost two days,
/// so the pump page shows a live pod and the glucose chart has basal bars.
///
/// Only the store is filled, through the same calls activation and the hourly
/// basal booking use; the in-memory demo pod (`demo_pod.dart`) answers every
/// status request with a running pod. The key is zeros: nothing is ever
/// encrypted, because there is no radio.
class DemoPump {
  DemoPump(this.now);

  final DateTime now;

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
    await store.saveLastStatus(PodStatusResponse(_statusBody), now);
  }

  /// A status frame as the pod sends it: running on its schedule, 82 U given
  /// and 38.5 U left, so the reservoir bar has a reading to show.
  Uint8List get _statusBody {
    final body = Uint8List(10);
    body[0] = 0x1d;
    body[1] =
        (PodDeliveryStatus.basalActive.value << 4) |
        PodLifecycleStatus.runningAboveMinimumVolume.value;
    ByteData.view(body.buffer)
      ..setUint32(2, deliveredPulses << 15)
      ..setUint32(6, (age.inMinutes << 10) | reservoirPulses);
    return body;
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
