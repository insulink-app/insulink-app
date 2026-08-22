import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_backup_restore.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/pump_sync.dart';

import 'fake_secure_storage.dart';

/// Letting go of a pod, whichever way it happens: deactivating it, discarding a
/// half-finished activation, or dropping one that answers nothing.
///
/// The account is what offers a pod back after a reinstall, so a pod dropped
/// only locally goes on being suggested at every launch with the user having
/// already dealt with it once. All three paths used to leave it in that state.
void main() {
  late Map<String, String> backing;
  late PodStore store;
  late RecordingPumpSync sync;

  setUp(() async {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
    sync = RecordingPumpSync();
    await store.savePairing(
      uniqueId: 4242,
      longTermKey: Uint8List(16),
      lotNumber: 1,
      podSequenceNumber: 2,
      activatedAt: DateTime.now(),
    );
  });

  Future<void> letGo() => PodBackupRestore(store, sync: sync).letGo();

  test('the account is told the pod is gone', () async {
    await store.saveBackendPumpId('pump-1');

    await letGo();

    expect(sync.discarded, ['pump-1']);
  });

  test('the pod is forgotten locally too', () async {
    await store.saveBackendPumpId('pump-1');

    await letGo();

    expect(store.hasPod, isFalse);
  });

  /// The id lives in the same record the local forget clears, so the order is
  /// the whole trick: read it, tell the account, then forget.
  test('a pod never mirrored has nothing to tell', () async {
    await letGo();

    expect(sync.discarded, isEmpty);
    expect(store.hasPod, isFalse);
  });

  /// A phone with no signal must still be able to let go of a pod. The offer
  /// card's own discard is the way back from a call that did not land, which is
  /// why that button exists separately.
  test('a refused call still forgets the pod', () async {
    await store.saveBackendPumpId('pump-1');
    sync.accept = false;

    await letGo();

    expect(store.hasPod, isFalse);
  });

  /// The two failures fall in opposite directions and only one is recoverable. A
  /// pod forgotten locally while the account still holds it is offered back by
  /// the card. A pod the app refuses to let go of because a network call threw is
  /// the state there was no way out of.
  test('a throwing call still forgets the pod', () async {
    await store.saveBackendPumpId('pump-1');
    sync.throwOnDiscard = true;

    await letGo();

    expect(store.hasPod, isFalse);
  });
}

/// A [PumpSync] that records instead of reaching the network.
class RecordingPumpSync implements PumpSync {
  final List<String> discarded = <String>[];
  bool accept = true;
  bool throwOnDiscard = false;

  @override
  Future<bool> discard(String pumpId, BuildContext? context) async {
    if (throwOnDiscard) {
      throw Exception('no route to host');
    }
    discarded.add(pumpId);
    return accept;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
