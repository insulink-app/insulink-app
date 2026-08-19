import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_store.dart';

import 'fake_secure_storage.dart';

void main() {
  late Map<String, String> backing;
  late PodStore store;

  setUp(() {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  test('a store with no pod reports none', () {
    expect(store.hasPod, isFalse);
    expect(store.uniqueId, isNull);
    expect(store.longTermKey, isNull);
  });

  test('a pairing is remembered as a whole', () async {
    await store.savePairing(
      uniqueId: 4242,
      longTermKey: Uint8List.fromList(List<int>.filled(16, 7)),
      lotNumber: 135556289,
      podSequenceNumber: 681767,
      activatedAt: DateTime(2026, 3, 1, 9, 30),
    );
    expect(store.hasPod, isTrue);
    expect(store.uniqueId, 4242);
    expect(store.longTermKey, Uint8List.fromList(List<int>.filled(16, 7)));
    expect(store.lotNumber, 135556289);
    expect(store.podSequenceNumber, 681767);
    expect(store.activatedAt, DateTime(2026, 3, 1, 9, 30));
  });

  test('the EAP sequence is reserved before use and never handed out twice', () async {
    expect(store.nextEapSequence, 1);
    expect(await store.reserveEapSequence(), 1);
    expect(store.nextEapSequence, 2);
    expect(await store.reserveEapSequence(), 2);
    expect(await store.reserveEapSequence(), 3);
  });

  test('a resynchronised EAP sequence replaces the stored one', () async {
    await store.reserveEapSequence();
    await store.saveSynchronizedEapSequence(350);
    expect(store.nextEapSequence, 350);
    expect(await store.reserveEapSequence(), 350);
  });

  test('the command sequence is kept inside four bits', () async {
    expect(store.commandSequence, 0);
    await store.saveCommandSequence(9);
    expect(store.commandSequence, 9);
    await store.saveCommandSequence(17);
    expect(store.commandSequence, 1);
  });

  test('forgetting a pod clears every trace of it', () async {
    await store.savePairing(
      uniqueId: 4242,
      longTermKey: Uint8List.fromList(List<int>.filled(16, 7)),
      lotNumber: 1,
      podSequenceNumber: 2,
      activatedAt: DateTime(2026, 3, 1),
    );
    await store.saveBleAddress('AA:BB:CC:DD:EE:FF');
    await store.reserveEapSequence();
    await store.saveCommandSequence(5);

    await store.forgetPod();

    expect(store.hasPod, isFalse);
    expect(store.bleAddress, isNull);
    expect(store.activationStep, isNull);
    expect(store.nextEapSequence, 1);
    expect(store.commandSequence, 0);
    expect(backing.keys.where((key) => key.startsWith('pod.')), isEmpty);
  });

  group('a newly paired pod starts its counters from scratch', () {
    /// A fresh pod has never seen a session or a command. Carrying a previous
    /// pod's numbers over makes it reject the first handshake.
    test('pairing with a reset zeroes both counters', () async {
      await store.saveSynchronizedEapSequence(350);
      await store.saveCommandSequence(9);

      await store.savePairing(
        uniqueId: 4241,
        longTermKey: Uint8List.fromList(List<int>.filled(16, 7)),
        lotNumber: 1,
        podSequenceNumber: 2,
        activatedAt: DateTime(2026, 3, 1),
        resetSessionCounters: true,
      );

      expect(store.nextEapSequence, 1);
      expect(store.commandSequence, 0);
    });

    /// Restoring a pod that is ALREADY running must keep its counters exactly —
    /// resetting them would make the pod refuse everything the app then sends.
    test('a restore preserves the counters it was given', () async {
      await store.adoptFromBackend(
        pumpId: 'pump-1',
        uniqueId: 4241,
        longTermKey: Uint8List.fromList(List<int>.filled(16, 7)),
        lotNumber: 1,
        podSequenceNumber: 2,
        activatedAt: DateTime(2026, 3, 1),
        expiryHours: 80,
        eapSequence: 42,
        commandSequence: 7,
        messageSequence: 91,
      );

      expect(store.nextEapSequence, 42);
      expect(store.commandSequence, 7);
      expect(store.messageSequence, 91);
    });
  });

  group('the message-packet counter runs across sessions', () {
    /// A different counter from the command sequence: it numbers the PACKETS,
    /// is a byte wide, and the pod keeps counting it whether or not a new session
    /// was established in between. A session that restarted it would put every
    /// packet it sent out of step with what the pod expects.
    test('it is kept apart from the command sequence', () async {
      await store.saveCommandSequence(9);
      await store.saveMessageSequence(200);

      expect(store.commandSequence, 9);
      expect(store.messageSequence, 200);
    });

    test('it wraps inside the byte the header gives it', () async {
      await store.saveMessageSequence(259);
      expect(store.messageSequence, 3);
    });

    test('a newly paired pod starts it at zero', () async {
      await store.saveMessageSequence(77);
      await store.savePairing(
        uniqueId: 4241,
        longTermKey: Uint8List.fromList(List<int>.filled(16, 7)),
        lotNumber: 1,
        podSequenceNumber: 2,
        activatedAt: DateTime(2026, 3, 1),
        resetSessionCounters: true,
      );

      expect(store.messageSequence, 0);
    });

    test('forgetting a pod clears it', () async {
      await store.saveMessageSequence(77);
      await store.forgetPod();
      expect(store.messageSequence, 0);
    });
  });
}
