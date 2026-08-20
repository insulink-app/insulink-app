import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
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
  PodBleLink(this.device, {this.onLog});

  final BluetoothDevice device;

  /// Where every frame in and out is reported. Without it a pod that simply says
  /// nothing is indistinguishable from one that said something we misread.
  final void Function(String line)? onLog;

  void _log(String line) {
    final sink = onLog;
    if (sink == null) {
      debugPrint('pod link: $line');
      return;
    }
    sink(line);
  }

  static String _hex(Uint8List frame) =>
      frame.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');

  final Map<PodCharacteristic, Queue<Uint8List>> _queues = {
    PodCharacteristic.command: Queue<Uint8List>(),
    PodCharacteristic.data: Queue<Uint8List>(),
  };
  final Map<PodCharacteristic, BluetoothCharacteristic> _characteristics = {};
  final Map<PodCharacteristic, Completer<void>> _waiters = {};
  final List<StreamSubscription<List<int>>> _subscriptions = [];

  /// Connects, discovers the pod service, greets the pod and subscribes to both
  /// characteristics.
  ///
  /// [hello] is written to the command characteristic BEFORE indications are
  /// enabled, in exactly the reference driver's order: hello, then command
  /// subscription, then data. Its own doc comment calls enabling indications
  /// "the signal the pod can start sending back data" — so the pod has to know
  /// who is talking before that signal arrives, and every frame the pod sends
  /// is an answer to ours, so nothing can be missed by subscribing after.
  ///
  /// `mtu: null` keeps flutter_blue_plus from negotiating its default 512-byte
  /// MTU. The reference driver never negotiates one; every frame in this
  /// protocol is 20 bytes, and a 2018-era pod firmware is not the place to be
  /// the first to try.
  Future<void> open({
    Duration timeout = const Duration(seconds: 20),
    Uint8List? hello,
  }) async {
    await device.connect(timeout: timeout, mtu: null, license: License.nonprofit);
    _log('connected to ${device.remoteId}');
    // A pod that hangs up mid-exchange looks exactly like a pod that went quiet:
    // the next write still "succeeds" against a dead link and the read times
    // out. This is what tells the two apart.
    _subscriptions.add(
      device.connectionState
          .map<List<int>>((state) {
            _log('link state: ${state.name}${_reason(state)}');
            return const [];
          })
          .listen((_) {}),
    );
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
    }
    if (hello != null) {
      await write(PodCharacteristic.command, hello);
    }
    for (final wanted in PodCharacteristic.values) {
      final characteristic = _characteristics[wanted]!;
      _subscriptions.add(characteristic.onValueReceived.listen(
        (bytes) => _enqueue(wanted, Uint8List.fromList(bytes)),
      ));
      // INDICATIONS, not notifications. The pod's characteristics advertise
      // both, so the platform would otherwise pick notifications and the pod
      // would answer on a channel nobody is listening to: every write succeeds
      // and nothing ever comes back. The reference driver enables indications
      // explicitly, and the CGM's auth characteristic needed the same.
      await characteristic.setNotifyValue(true, forceIndications: true);
      _log('${wanted.name}: subscribed '
          '(notify=${characteristic.properties.notify}, '
          'indicate=${characteristic.properties.indicate})');
    }
  }

  /// Who ended the link and why.
  ///
  /// The single most useful thing a dropped pairing can tell us: code 19 is the
  /// POD hanging up, which means it disliked something we sent; a local code
  /// (8 supervision timeout, 22 local host) means the phone or the stack let go,
  /// and the pod is blameless. The fix is completely different either way.
  String _reason(BluetoothConnectionState state) {
    if (state != BluetoothConnectionState.disconnected) {
      return '';
    }
    final reason = device.disconnectReason;
    if (reason == null) {
      return ' (no reason reported)';
    }
    return ' (${reason.platform.name} code=${reason.code} "${reason.description}")';
  }

  void _enqueue(PodCharacteristic characteristic, Uint8List frame) {
    _log('<- ${characteristic.name} ${_hex(frame)}');
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
    _log('-> ${characteristic.name} ${_hex(frame)}');
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
