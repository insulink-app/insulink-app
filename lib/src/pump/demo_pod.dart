import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:insulink/src/pump/pod_connection.dart';
import 'package:insulink/src/pump/pod_scanner.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_ids.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';
import 'package:insulink/src/pump/protocol/pod_message_io.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/protocol/pod_stop_delivery_command.dart';
import 'package:insulink/src/pump/protocol/pod_session_keys.dart';
import 'package:insulink/src/pump/protocol/session_cipher.dart';

/// TEMPORARY — a pod that only exists in memory, so the activation wizard and
/// the pump page can be walked through without hardware.
///
/// Deliberately shallow: it fakes the ANSWERS, not the protocol. Nothing here is
/// encrypted, fragmented or checksummed, so it proves nothing about the driver —
/// it only drives the screens.
///
/// **To remove:** set [demoPodEnabled] to false, then delete this file and the
/// two `podConnectionFor` call sites (`PodController`, `PodActivationController`).
const bool demoPodEnabled = true;

/// The one place that decides whether the app talks to a radio or to this file.
PodConnection podConnectionFor(PodStore store) =>
    demoPodEnabled ? DemoPodConnection(store: store) : PodConnection(store: store);

/// How long the fake search takes. Long enough to watch the spinner and try the
/// cancel button, short enough not to be tedious.
const Duration _searchTime = Duration(seconds: 5);

class DemoPodConnection extends PodConnection {
  DemoPodConnection({required super.store});

  bool _stopped = false;

  @override
  Future<PodActivationSession> beginActivation({
    required Future<bool> Function(DiscoveredPod pod) confirmIrreversible,
  }) async {
    _stopped = false;
    await Future<void>.delayed(_searchTime);
    if (_stopped) {
      throw PodLinkException('Pod search stopped');
    }
    final pod = DiscoveredPod(
      device: BluetoothDevice.fromId('DE:M0:00:00:00:01'),
      podId: DiscoveredPod.unactivatedPodId,
      lotNumber: 135556289,
      podSequenceNumber: 681767,
    );
    if (!await confirmIrreversible(pod)) {
      throw PodLinkException('Pairing cancelled before it began');
    }
    const podUniqueId = 4241;
    _DemoSession.reset();
    await store.saveBleAddress(pod.device.remoteId.str);
    await store.savePairing(
      uniqueId: podUniqueId,
      longTermKey: Uint8List.fromList(List<int>.filled(16, 0xDE)),
      lotNumber: pod.lotNumber,
      podSequenceNumber: pod.podSequenceNumber,
      activatedAt: DateTime.now(),
      resetSessionCounters: true,
    );
    return PodActivationSession(
      session: _DemoSession(),
      podUniqueId: podUniqueId,
    );
  }

  @override
  Future<PodSession> openSession({
    bool stillAdvertisingUnactivated = false,
    bool allowScan = true,
  }) async {
    _stopped = false;
    await Future<void>.delayed(const Duration(seconds: 1));
    if (_stopped) {
      throw PodLinkException('Pod search stopped');
    }
    return _DemoSession();
  }

  @override
  Future<void> stop() async {
    _stopped = true;
  }

  @override
  Future<void> close() async {}
}

/// Answers every command with something the wizard accepts.
class _DemoSession extends PodSession {
  _DemoSession()
      : super(
          messageIo: PodMessageIo(_DeadLink()),
          addresses: const PodAddressPair(podUniqueId: 4241),
          keys: PodSessionKeys(
            confidentialityKey: Uint8List(16),
            nonce: SessionNonce(prefix: Uint8List(8), sequence: 0),
            messageSequence: 0,
            eapSequence: 1,
          ),
        );

  /// Whether the fake pod has been told to stop. Static, because a session is
  /// built fresh per operation and the pod would not forget in between.
  ///
  /// Load-bearing for deactivation: the real controller only forgets a pod that
  /// REPORTS itself suspended, so a demo that always claimed to be delivering
  /// could never be deactivated.
  static bool _suspended = false;

  /// A newly activated demo pod is running again, whatever the last one did.
  static void reset() {
    _suspended = false;
  }

  @override
  Future<PodResponse> run(PodCommand command) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    switch (command.type) {
      case PodCommandType.getVersion:
        return PodVersionResponse(_versionBody);
      case PodCommandType.setUniqueId:
        return PodSetUniqueIdResponse(_identityBody);
      case PodCommandType.programBolus:
        return PodStatusResponse(_statusBody(
          lifecycle: PodLifecycleStatus.priming,
          delivery: PodDeliveryStatus.bolusAndBasalActive,
          bolusPulses: 52,
        ));
      case PodCommandType.stopDelivery:
        // Only a suspend-everything stops the pod. Ending a temporary rate is
        // also a stop-delivery command, but it hands the schedule back.
        _suspended = _stopsEverything(command);
        return PodStatusResponse(_statusBody());
      case PodCommandType.deactivate:
        _suspended = true;
        return PodStatusResponse(_statusBody(
          lifecycle: PodLifecycleStatus.deactivated,
          delivery: PodDeliveryStatus.suspended,
        ));
      case PodCommandType.programBasal:
      case PodCommandType.programTempBasal:
        _suspended = false;
        return PodStatusResponse(_statusBody());
      default:
        return PodStatusResponse(_statusBody());
    }
  }

  /// Whether a stop-delivery command names every kind of delivery, rather than
  /// just the temporary basal.
  bool _stopsEverything(PodCommand command) =>
      command is PodStopDeliveryCommand &&
      command.target == PodDeliveryTarget.all;

  Uint8List get _versionBody {
    final body = Uint8List(23);
    body[0] = 0x01;
    body[1] = 0x15;
    body[9] = PodLifecycleStatus.filled.value;
    ByteData.view(body.buffer)
      ..setUint32(10, 135556289)
      ..setUint32(14, 681767);
    return body;
  }

  /// The prime rate is one eighth-second per pulse rather than the real eight, so
  /// the priming wait is seconds instead of the best part of a minute.
  Uint8List get _identityBody {
    final body = Uint8List(29);
    body[0] = 0x01;
    body[1] = 0x1b;
    body[4] = 16;
    body[5] = 1;
    body[6] = 10;
    body[7] = 52;
    body[8] = 80;
    body[16] = PodLifecycleStatus.uniqueIdSet.value;
    ByteData.view(body.buffer)
      ..setUint32(17, 135556289)
      ..setUint32(21, 681767)
      ..setUint32(25, 4242);
    return body;
  }

  Uint8List _statusBody({
    PodLifecycleStatus? lifecycle,
    PodDeliveryStatus? delivery,
    int bolusPulses = 0,
  }) {
    final state = lifecycle ??
        (_suspended
            ? PodLifecycleStatus.deactivated
            : PodLifecycleStatus.runningAboveMinimumVolume);
    final running = delivery ??
        (_suspended ? PodDeliveryStatus.suspended : PodDeliveryStatus.basalActive);
    final body = Uint8List(10);
    body[0] = 0x1d;
    body[1] = (running.value << 4) | state.value;
    ByteData.view(body.buffer)
      ..setUint32(2, bolusPulses & 0x7FF)
      ..setUint32(6, 700);
    return body;
  }
}

/// Never spoken to: [_DemoSession] overrides the one method that would.
class _DeadLink implements PodLink {
  @override
  Future<void> write(PodCharacteristic characteristic, Uint8List frame) async {}

  @override
  Future<Uint8List?> read(PodCharacteristic characteristic, Duration timeout) async =>
      null;

  @override
  Uint8List? peek(PodCharacteristic characteristic) => null;

  @override
  void flush(PodCharacteristic characteristic) {}
}
