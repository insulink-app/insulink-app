import 'package:insulink/src/pump/pod_ble_link.dart';
import 'package:insulink/src/pump/pod_scanner.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_ids.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';
import 'package:insulink/src/pump/protocol/pod_message_io.dart';
import 'package:insulink/src/pump/protocol/pod_pairing.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/protocol/pod_session_establisher.dart';
import 'package:insulink/src/pump/protocol/pod_session_keys.dart';

/// Opens a working session with a pod: find it, connect, and establish keys.
///
/// The pod closes its link between exchanges, so a session is short-lived — this
/// is built fresh for each conversation rather than held open.
///
/// A session is only ever established for a pod whose long-term key is already
/// stored. [pairNewPod] is the one path that creates that key, and it stores it
/// as soon as the pod may have kept it: a key we discarded but the pod retained
/// would leave a pod nobody can stop.
class PodConnection {
  PodConnection({
    required this.store,
    this.scanner = const PodScanner(),
  });

  final PodStore store;
  final PodScanner scanner;

  PodBleLink? _link;

  /// The link currently held, if any, so a caller can close it.
  PodBleLink? get link => _link;

  /// Connects to the already-paired pod and establishes a session.
  ///
  /// Retries once after a resynchronisation, because the pod's answer to a stale
  /// EAP sequence number is the corrected value — the second attempt uses it.
  /// Anything else is not retried here.
  Future<PodSession> openSession() async {
    final uniqueId = store.uniqueId;
    final longTermKey = store.longTermKey;
    if (uniqueId == null || longTermKey == null) {
      throw PodLinkException('No pod is paired');
    }
    final messageIo = await _connect(uniqueId);
    final addresses = PodAddressPair(podUniqueId: uniqueId);

    for (var attempt = 0; attempt < 2; attempt++) {
      final eapSequence = await store.reserveEapSequence();
      try {
        final keys = await PodSessionEstablisher(
          messageIo: messageIo,
          addresses: addresses,
          longTermKey: longTermKey,
          eapSequence: eapSequence,
          messageSequence: store.commandSequence,
        ).establish();
        return PodSession(
          messageIo: messageIo,
          addresses: addresses,
          keys: keys,
        );
      } on PodSessionResyncRequired catch (resync) {
        await store.saveSynchronizedEapSequence(resync.synchronizedEapSequence);
      }
    }
    throw PodSessionException('Pod rejected the session twice running');
  }

  /// Pairs a new pod and returns a session ready to activate it.
  ///
  /// [confirmIrreversible] is called once the pod has been found and before any
  /// pairing message goes out. Returning false aborts while the pod is still
  /// untouched — the last moment at which that is true.
  ///
  /// The key is stored the instant pairing completes, before the pod has even
  /// been asked its version. That ordering is deliberate: from the moment the pod
  /// may hold the key, we must be able to reach it again, and the alternative
  /// (store it once activation succeeds) leaves a window in which a crash strands
  /// a pod nobody can command.
  ///
  /// The pod's address does not change when it is later given its id: the id it
  /// is assigned IS the address it already answers on, so one session spans the
  /// whole activation.
  Future<PodActivationSession> beginActivation({
    required Future<bool> Function(DiscoveredPod pod) confirmIrreversible,
  }) async {
    final pod = await scanner.scanForSingle(
      wantedPodId: DiscoveredPod.unactivatedPodId,
    );
    if (!await confirmIrreversible(pod)) {
      throw PodLinkException('Pairing cancelled before it began');
    }
    final link = PodBleLink(pod.device);
    _link = link;
    await link.open();
    final messageIo = PodMessageIo(link);
    await messageIo.sayHello(PodAddressPair.controllerId);

    const addresses = PodAddressPair(podUniqueId: null);
    final pairing = await PodPairing(
      messageIo: messageIo,
      addresses: addresses,
    ).negotiate();

    final podUniqueId = addresses.podId.value;
    await store.savePairing(
      uniqueId: podUniqueId,
      longTermKey: pairing.longTermKey,
      lotNumber: pod.lotNumber,
      podSequenceNumber: pod.podSequenceNumber,
      activatedAt: DateTime.now(),
    );
    await store.saveBleAddress(pod.device.remoteId.str);

    final keys = await PodSessionEstablisher(
      messageIo: messageIo,
      addresses: addresses,
      longTermKey: pairing.longTermKey,
      eapSequence: await store.reserveEapSequence(),
      messageSequence: pairing.messageSequence,
    ).establish();

    return PodActivationSession(
      session: PodSession(
        messageIo: messageIo,
        addresses: addresses,
        keys: keys,
      ),
      podUniqueId: podUniqueId,
    );
  }

  Future<PodMessageIo> _connect(int uniqueId) async {
    final pod = await scanner.scanForSingle(wantedPodId: uniqueId);
    final link = PodBleLink(pod.device);
    _link = link;
    await link.open();
    final messageIo = PodMessageIo(link);
    await messageIo.sayHello(PodAddressPair.controllerId);
    await store.saveBleAddress(pod.device.remoteId.str);
    return messageIo;
  }

  /// Closes the link, if one is open.
  Future<void> close() async {
    final link = _link;
    _link = null;
    await link?.close();
  }
}

/// A session on a pod that is being activated, with the id the activation will
/// assign to it.
class PodActivationSession {
  const PodActivationSession({required this.session, required this.podUniqueId});

  final PodSession session;
  final int podUniqueId;
}
