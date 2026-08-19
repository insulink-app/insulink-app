import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';

/// A pod found in a scan, with the identity it advertises.
class DiscoveredPod {
  const DiscoveredPod({
    required this.device,
    required this.podId,
    required this.lotNumber,
    required this.podSequenceNumber,
  });

  final BluetoothDevice device;

  /// The address the pod answers on. A pod that has never been activated
  /// advertises [unactivatedPodId].
  final int podId;

  final int lotNumber;
  final int podSequenceNumber;

  bool get isUnactivated => podId == unactivatedPodId;

  /// The address a filled but never-activated pod advertises.
  static const int unactivatedPodId = 0xFFFFFFFE;
}

/// Finds pods over BLE.
///
/// A pod encodes its id, lot and sequence number across nine 16-bit service ids
/// in its advertisement, so a scan can tell a new pod from an already-activated
/// one, and one pod from another, before connecting.
///
/// Finding more than one candidate is an error rather than a pick-the-strongest:
/// activating the wrong pod is irreversible, and two pods in range is exactly
/// when a wrong guess is most likely.
class PodScanner {
  const PodScanner();

  static const int _expectedServiceIds = 9;
  static const String _mainServiceId = podAdvertisedServiceId;
  static const String _thirdServiceId = '000a';

  /// Ends a scan this app has running, so a wait for one can be cut short.
  ///
  /// Safe when nothing is scanning: the platform call is a no-op there.
  Future<void> stop() => FlutterBluePlus.stopScan();

  /// Scans for pods, returning every valid candidate seen within [timeout].
  ///
  /// [wantedPodId] filters to one pod; pass [DiscoveredPod.unactivatedPodId] to
  /// look for a fresh pod, or an activated pod's id to reconnect to it.
  Future<List<DiscoveredPod>> scan({
    required int wantedPodId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final found = <String, DiscoveredPod>{};
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final pod = _read(result);
        if (pod != null && pod.podId == wantedPodId) {
          found[result.device.remoteId.str] = pod;
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(podScanServiceUuid)],
        timeout: timeout,
      );
      await FlutterBluePlus.isScanning.where((running) => !running).first;
    } finally {
      await subscription.cancel();
      await FlutterBluePlus.stopScan();
    }
    return found.values.toList();
  }

  /// Finds exactly one pod, or explains why it could not.
  ///
  /// An empty result is tried once more. Only one BLE scan can run at a time, and
  /// the CGM service scans on its own schedule — starting one there stops ours
  /// mid-flight, which looks exactly like "no pod in range". A second attempt costs
  /// half a minute and saves a filled pod from being written off.
  ///
  /// [preferredAddress] settles the one ambiguity a pod id cannot: every pod this
  /// app activates is given the SAME id, so the pod that was just replaced answers
  /// to the same address as the one on the body until its battery gives out. The
  /// stored BLE address is what tells them apart. Without a match the ambiguity
  /// stands and nothing is chosen — commanding the wrong pod is worse than failing.
  ///
  /// [isCancelled] is asked between the two attempts and before the result is
  /// used, so a user who stopped the search does not sit through a second scan or
  /// end up connected to a pod they no longer wanted.
  Future<DiscoveredPod> scanForSingle({
    required int wantedPodId,
    Duration timeout = const Duration(seconds: 30),
    String? preferredAddress,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    var found = await scan(wantedPodId: wantedPodId, timeout: timeout);
    if (found.isEmpty && !cancelled()) {
      found = await scan(wantedPodId: wantedPodId, timeout: timeout);
    }
    if (cancelled()) {
      throw PodLinkException('Pod search stopped');
    }
    if (found.isEmpty) {
      throw PodLinkException('No pod found');
    }
    if (found.length == 1) {
      return found.single;
    }
    return _theKnownOne(found, preferredAddress);
  }

  /// The pod at [preferredAddress] among several that answer to the same id.
  DiscoveredPod _theKnownOne(
    List<DiscoveredPod> found,
    String? preferredAddress,
  ) {
    final known = found
        .where((pod) => pod.device.remoteId.str == preferredAddress)
        .toList();
    if (known.length == 1) {
      return known.single;
    }
    throw PodLinkException(
      '${found.length} pods in range — move away from the others and retry',
    );
  }

  /// Reads a pod's identity out of its advertisement, or null if the
  /// advertisement is not a pod's.
  DiscoveredPod? _read(ScanResult result) {
    final ids = result.advertisementData.serviceUuids
        .map((uuid) => _shortId(uuid))
        .toList();
    if (ids.length != _expectedServiceIds ||
        ids[0] != _mainServiceId ||
        ids[2] != _thirdServiceId) {
      return null;
    }
    final podId = int.tryParse('${ids[3]}${ids[4]}', radix: 16);
    final lotAndSequence = '${ids[5]}${ids[6]}${ids[7]}${ids[8]}';
    final lot = int.tryParse(lotAndSequence.substring(0, 10), radix: 16);
    final sequence = int.tryParse(lotAndSequence.substring(10), radix: 16);
    if (podId == null || lot == null || sequence == null) {
      return null;
    }
    return DiscoveredPod(
      device: result.device,
      podId: podId,
      lotNumber: lot,
      podSequenceNumber: sequence,
    );
  }

  /// The 16-bit part of a Bluetooth base UUID.
  String _shortId(Guid uuid) {
    final full = uuid.str128.replaceAll('-', '');
    return full.substring(4, 8).toLowerCase();
  }
}
