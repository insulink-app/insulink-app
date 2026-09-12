import 'dart:async';
import 'package:flutter/foundation.dart';
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
  const PodScanner({this.onLog});

  /// Where the scan reports what it saw. Without it a failed search is a bare
  /// "no pod found" with nothing behind it, which is no help at all when the pod
  /// is lying right there beeping.
  final void Function(String line)? onLog;

  void _log(String line) {
    final sink = onLog;
    if (sink == null) {
      debugPrint('pod scan: $line');
      return;
    }
    sink(line);
  }

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
  /// [stopAt] is the address whose appearance ends the scan early.
  ///
  /// Without it the scan runs its whole window even though the pod was seen in
  /// the first second, and every pod operation pays that as dead time. Only ever
  /// passed when the exact device is already known, because stopping early gives
  /// up the chance to notice a SECOND pod answering to the same id — a risk worth
  /// taking to reconnect to a pod we can name, and not worth taking while pairing
  /// one we cannot.
  ///
  /// [filtered] false scans for everything and sorts the results out here.
  ///
  /// The filtered scan is the right one to prefer: Android returns fewer results
  /// and delivers them with the screen off. But a service-uuid filter that does
  /// not match returns silence that is indistinguishable from an absent pod, so
  /// the fallback exists to tell those two apart.
  Future<List<DiscoveredPod>> scan({
    required int wantedPodId,
    Duration timeout = const Duration(seconds: 30),
    bool filtered = true,
    String? stopAt,
  }) async {
    final found = <String, DiscoveredPod>{};
    final seen = <String>{};
    final wantedAppeared = Completer<void>();
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        _inspect(result, wantedPodId, found, seen);
      }
      if (stopAt != null &&
          found.containsKey(stopAt) &&
          !wantedAppeared.isCompleted) {
        wantedAppeared.complete();
      }
    });
    try {
      _log(
        'started, filter=${filtered ? podAdvertisedServiceId : 'none'}, '
        'want=0x${wantedPodId.toRadixString(16)}',
      );
      await FlutterBluePlus.startScan(
        withServices: filtered ? [Guid(podScanServiceUuid)] : const [],
        timeout: timeout,
      );
      await Future.any([
        FlutterBluePlus.isScanning.where((running) => !running).first,
        wantedAppeared.future,
      ]);
    } finally {
      await subscription.cancel();
      await FlutterBluePlus.stopScan();
      _log(
        'finished, ${seen.length} device(s) seen, '
        '${found.length} matching pod(s)',
      );
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
    var found = await scan(
      wantedPodId: wantedPodId,
      timeout: timeout,
      stopAt: preferredAddress,
    );
    if (found.isEmpty && !cancelled()) {
      // Second pass unfiltered. A filter that does not match returns the same
      // silence as an absent pod, and this is what tells them apart — including
      // in the log, which now names every device it saw and why it passed on it.
      found = await scan(
        wantedPodId: wantedPodId,
        timeout: timeout,
        filtered: false,
        stopAt: preferredAddress,
      );
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

  /// Records one scan result and says why it was or was not taken.
  ///
  /// Every rejection is logged with the advertisement that caused it. A pod that
  /// is seen but thrown out looks exactly like a pod that is not there, and the
  /// two need completely different fixes.
  void _inspect(
    ScanResult result,
    int wantedPodId,
    Map<String, DiscoveredPod> found,
    Set<String> seen,
  ) {
    final address = result.device.remoteId.str;
    if (!seen.add(address)) {
      return;
    }
    final ids = result.advertisementData.serviceUuids
        .map((uuid) => _shortId(uuid))
        .toList();
    final pod = _read(result);
    if (pod == null) {
      _log('ignored $address, ${ids.length} service id(s) $ids');
      return;
    }
    if (pod.podId != wantedPodId) {
      _log(
        'ignored $address, pod 0x${pod.podId.toRadixString(16)} '
        'is not the one wanted',
      );
      return;
    }
    _log(
      'found $address, pod 0x${pod.podId.toRadixString(16)}, '
      'lot ${pod.lotNumber}, seq ${pod.podSequenceNumber}',
    );
    found[address] = pod;
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
