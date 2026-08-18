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
}
