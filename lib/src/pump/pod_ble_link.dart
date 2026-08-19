import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';

/// A [PodLink] over a real BLE connection.
///
/// Notifications are drained into a queue per characteristic rather than handed
/// to a listener, because the protocol is strictly request/response: a control
/// word that arrives while the driver is still writing has to wait its turn, and
/// a broadcast stream would discard it.
///
/// Writes use write-with-response. The pod's flow control depends on knowing a
/// fragment landed, and a fire-and-forget write would let the driver run ahead of
/// a pod that is still catching up.
class PodBleLink implements PodLink {
  PodBleLink(this.device);

  final BluetoothDevice device;

  final Map<PodCharacteristic, Queue<Uint8List>> _queues = {
    PodCharacteristic.command: Queue<Uint8List>(),
    PodCharacteristic.data: Queue<Uint8List>(),
  };
  final Map<PodCharacteristic, BluetoothCharacteristic> _characteristics = {};
  final Map<PodCharacteristic, Completer<void>> _waiters = {};
  final List<StreamSubscription<List<int>>> _subscriptions = [];

  /// Connects, discovers the pod service, and subscribes to both
  /// characteristics.
  ///
  /// Both subscriptions are live before any command is written — the pod answers
  /// immediately, and a subscription set up after the write loses the reply.
  Future<void> open({Duration timeout = const Duration(seconds: 20)}) async {
    await device.connect(timeout: timeout, license: License.nonprofit);
    final services = await device.discoverServices();
    final service = services.firstWhere(
      (candidate) => candidate.uuid.str128.toLowerCase() == podServiceUuid,
      orElse: () => throw PodLinkException('Pod service not found on ${device.remoteId}'),
    );
    for (final wanted in PodCharacteristic.values) {
      final characteristic = service.characteristics.firstWhere(
        (candidate) => candidate.uuid.str128.toLowerCase() == wanted.uuid,
        orElse: () =>
            throw PodLinkException('Pod characteristic ${wanted.name} not found'),
      );
      _characteristics[wanted] = characteristic;
      _subscriptions.add(characteristic.onValueReceived.listen(
        (bytes) => _enqueue(wanted, Uint8List.fromList(bytes)),
      ));
      await characteristic.setNotifyValue(true);
    }
  }

  void _enqueue(PodCharacteristic characteristic, Uint8List frame) {
    _queues[characteristic]!.add(frame);
    final waiter = _waiters.remove(characteristic);
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }

  @override
  Future<void> write(PodCharacteristic characteristic, Uint8List frame) async {
    final target = _characteristics[characteristic];
    if (target == null) {
      throw PodLinkException('Link not open');
    }
    await target.write(frame, withoutResponse: false);
  }

  @override
  Future<Uint8List?> read(PodCharacteristic characteristic, Duration timeout) async {
    final queue = _queues[characteristic]!;
    if (queue.isNotEmpty) {
      return queue.removeFirst();
    }
    final waiter = Completer<void>();
    _waiters[characteristic] = waiter;
    try {
      await waiter.future.timeout(timeout);
    } on TimeoutException {
      _waiters.remove(characteristic);
      return null;
    }
    return queue.isEmpty ? null : queue.removeFirst();
  }

  @override
  Uint8List? peek(PodCharacteristic characteristic) {
    final queue = _queues[characteristic]!;
    return queue.isEmpty ? null : queue.first;
  }

  @override
  void flush(PodCharacteristic characteristic) =>
      _queues[characteristic]!.clear();

  /// Closes the link. Safe to call more than once, and safe on a link the pod has
  /// already dropped — which is the normal state after waiting for it to finish
  /// priming, so a throw here would fail the activation that is about to reconnect.
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _characteristics.clear();
    for (final waiter in _waiters.values) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _waiters.clear();
    try {
      await device.disconnect();
    } on Exception {
      return;
    }
  }
}
