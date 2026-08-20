import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:insulink/src/base/rust_core.dart';
import 'package:insulink/src/pump/pod_ble_link.dart';
import 'package:insulink/src/pump/pod_scanner.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/key_exchange.dart';
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
  PodSession? _openedSession;
  bool _stopped = false;

  /// The link currently held, if any, so a caller can close it.
  PodBleLink? get link => _link;

  /// Connects to the already-paired pod and establishes a session.
  ///
  /// Retries once after a resynchronisation, because the pod's answer to a stale
  /// EAP sequence number is the corrected value — the second attempt uses it.
  /// Anything else is not retried here.
  /// A paired pod is always looked up by its ASSIGNED id. It adopts the address
  /// it was given in SP1 the moment pairing completes, long before the activation
  /// command that formally sets its id: real hardware advertises 0x1091 while
  /// still reporting lifecycle `filled`. There is no state in which a paired pod
  /// answers to the discovery address, so nothing looks for it here.
  /// [allowScan] false connects straight to the stored BLE address instead of
  /// scanning. The background service passes false: a scan there would compete
  /// with the CGM's, and Android wedges its scanner when two things scan around
  /// the clock — the documented multi-hour "0 devices found" stall. Mirrors the
  /// Fitbit monitor's known-band-only rule for the same reason.
  Future<PodSession> openSession({bool allowScan = true}) async {
    _stopped = false;
    final uniqueId = store.uniqueId;
    final longTermKey = store.longTermKey;
    if (uniqueId == null || longTermKey == null) {
      throw PodLinkException('No pod is paired');
    }
    final messageIo = await _connect(uniqueId, allowScan: allowScan);
    final addresses = PodAddressPair(podUniqueId: uniqueId);

    for (var attempt = 0; attempt < 2; attempt++) {
      final eapSequence = await store.reserveEapSequence();
      try {
        final keys = await PodSessionEstablisher(
          messageIo: messageIo,
          addresses: addresses,
          longTermKey: longTermKey,
          eapSequence: eapSequence,
          messageSequence: store.messageSequence,
        ).establish();
        return _remember(PodSession(
          messageIo: messageIo,
          addresses: addresses,
          keys: keys,
        ));
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
    _stopped = false;
    // The X25519 exchange below runs in Rust, and this isolate has never needed
    // it before: the CGM's crypto lives in the service isolate, which brings the
    // bridge up itself. Done before the scan so a missing bridge fails here,
    // rather than after a pod has been found and is waiting to be paired.
    await RustCore.ensureInitialised();
    final pod = await scanner.scanForSingle(
      wantedPodId: DiscoveredPod.unactivatedPodId,
      isCancelled: () => _stopped,
    );
    if (!await confirmIrreversible(pod)) {
      throw PodLinkException('Pairing cancelled before it began');
    }
    final link = PodBleLink(pod.device);
    _link = link;
    await link.open(
      hello: PodControlWord.helloFrom(PodAddressPair.controllerId),
    );
    final messageIo = PodMessageIo(link);

    const addresses = PodAddressPair(podUniqueId: null);
    final podUniqueId = addresses.podId.value;
    await store.saveBleAddress(pod.device.remoteId.str);

    final PodPairingResult pairing;
    try {
      pairing = await PodPairing(
        messageIo: messageIo,
        addresses: addresses,
        onKeyDerived: (longTermKey) => store.savePairing(
          uniqueId: podUniqueId,
          longTermKey: longTermKey,
          lotNumber: pod.lotNumber,
          podSequenceNumber: pod.podSequenceNumber,
          activatedAt: DateTime.now(),
          resetSessionCounters: true,
        ),
      ).negotiate();
    } on PodPairingMismatch {
      // The only failure that proves the key is wrong. Everything else leaves it
      // possibly good, and a possibly-good key is the difference between a pod
      // that can be picked up again and one that is scrap.
      await store.forgetPod();
      rethrow;
    }

    final keys = await PodSessionEstablisher(
      messageIo: messageIo,
      addresses: addresses,
      longTermKey: pairing.longTermKey,
      eapSequence: await store.reserveEapSequence(),
      messageSequence: pairing.messageSequence,
    ).establish();

    return PodActivationSession(
      session: _remember(PodSession(
        messageIo: messageIo,
        addresses: addresses,
        keys: keys,
      )),
      podUniqueId: podUniqueId,
    );
  }

  Future<PodMessageIo> _connect(
    int advertisedPodId, {
    bool allowScan = true,
  }) async {
    final device = allowScan
        ? (await scanner.scanForSingle(
            wantedPodId: advertisedPodId,
            preferredAddress: store.bleAddress,
            isCancelled: () => _stopped,
          )).device
        : _storedDevice();
    final link = PodBleLink(device);
    _link = link;
    await link.open(
      hello: PodControlWord.helloFrom(PodAddressPair.controllerId),
    );
    final messageIo = PodMessageIo(link);
    await store.saveBleAddress(device.remoteId.str);
    return messageIo;
  }

  /// The pod at its remembered address.
  ///
  /// A cold process that has never SEEN this address may fail to connect to it —
  /// the same OS quirk the G7 reconnect documents. The caller recovers by allowing
  /// one scan after a few failures ([PodMonitor.scanAfterFailures]), which teaches
  /// the OS the address without leaving a scanner running.
  BluetoothDevice _storedDevice() {
    final address = store.bleAddress;
    if (address == null || address.isEmpty) {
      throw PodLinkException('No pod address stored — connect once from the app');
    }
    return BluetoothDevice.fromId(address);
  }

  /// Cuts short whatever is in flight: ends a running scan and drops the link, so
  /// the call waiting on either fails instead of running to its timeout.
  ///
  /// Nothing stored is discarded. Every activation step is written before the next
  /// one runs, so an attempt stopped here RESUMES from where it got to rather than
  /// starting over — which matters, because starting over would re-send commands
  /// the pod has already carried out.
  Future<void> stop() async {
    _stopped = true;
    await scanner.stop();
    await close();
  }

  /// Holds on to the session so its counter can be persisted when the link is
  /// dropped, rather than leaving every caller to remember it.
  PodSession _remember(PodSession session) {
    _openedSession = session;
    return session;
  }

  /// Closes the link, if one is open, and records where the message-packet
  /// counter stands.
  ///
  /// That counter runs ACROSS sessions — the pod keeps counting it whether or not
  /// a new session was established in between — so a session that started it over
  /// would put every packet it sent out of step with what the pod expects.
  Future<void> close() async {
    final session = _openedSession;
    _openedSession = null;
    final link = _link;
    _link = null;
    try {
      if (session != null) {
        await store.saveMessageSequence(session.keys.messageSequence);
      }
    } finally {
      await link?.close();
    }
  }
}

/// A session on a pod that is being activated, with the id the activation will
/// assign to it.
class PodActivationSession {
  const PodActivationSession({required this.session, required this.podUniqueId});

  final PodSession session;
  final int podUniqueId;
}
