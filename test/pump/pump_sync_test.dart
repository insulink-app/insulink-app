import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/pump_sync.dart';

import 'fake_secure_storage.dart';

/// A blob shaped exactly like the one `PumpSync` writes.
Map<String, dynamic> blob({Map<String, dynamic> overrides = const {}}) => {
      'pump_type': 'OMNIPOD_DASH',
      'unique_id': 4241,
      'long_term_key': base64Encode(List<int>.filled(16, 7)),
      'lot_number': 135556289,
      'pod_sequence_number': 681767,
      'activated_at': DateTime(2026, 3, 1, 8, 0).millisecondsSinceEpoch,
      'expiry_hours': 80,
      'eap_sequence': 3,
      'command_sequence': 5,
      'ble_address': 'AA:BB:CC:DD:EE:FF',
      ...overrides,
    };

void main() {
  group('a stored pod is read back completely', () {
    test('every field the reconnect needs survives the round trip', () {
      final restore = PodRestore.fromBlob('pump-1', blob());
      expect(restore.pumpId, 'pump-1');
      expect(restore.uniqueId, 4241);
      expect(restore.longTermKey, List<int>.filled(16, 7));
      expect(restore.lotNumber, 135556289);
      expect(restore.podSequenceNumber, 681767);
      expect(restore.activatedAt, DateTime(2026, 3, 1, 8, 0));
      expect(restore.expiryHours, 80);
      expect(restore.eapSequence, 3);
      expect(restore.commandSequence, 5);
      expect(restore.bleAddress, 'AA:BB:CC:DD:EE:FF');
    });

    test('expiry follows the activation plus the pod lifetime', () {
      final restore = PodRestore.fromBlob('pump-1', blob());
      expect(restore.expiresAt, DateTime(2026, 3, 1, 8, 0).add(
        const Duration(hours: 80),
      ));
    });

    test('an old pod is reported as expired so it is not offered', () {
      final old = PodRestore.fromBlob('pump-1', blob(overrides: {
        'activated_at':
            DateTime.now().subtract(const Duration(days: 9)).millisecondsSinceEpoch,
      }));
      expect(old.isExpired, isTrue);
    });

    test('a running pod is not expired and reports what is left', () {
      final fresh = PodRestore.fromBlob('pump-1', blob(overrides: {
        'activated_at':
            DateTime.now().subtract(const Duration(hours: 10)).millisecondsSinceEpoch,
      }));
      expect(fresh.isExpired, isFalse);
      expect(fresh.remaining.inHours, closeTo(69, 1));
    });
  });

  group('a blob missing something essential is refused, not half-adopted', () {
    test('without a key there is no way to reach the pod', () {
      final broken = blob()..remove('long_term_key');
      expect(() => PodRestore.fromBlob('pump-1', broken), throwsA(anything));
    });

    test('without an id there is no address to talk to', () {
      final broken = blob()..remove('unique_id');
      expect(() => PodRestore.fromBlob('pump-1', broken), throwsA(anything));
    });

    test('without an activation time the expiry cannot be judged', () {
      final broken = blob()..remove('activated_at');
      expect(() => PodRestore.fromBlob('pump-1', broken), throwsA(anything));
    });
  });

  group('optional fields fall back rather than failing', () {
    test('the counters default to a safe starting point', () {
      final blobWithoutCounters = blob()
        ..remove('eap_sequence')
        ..remove('command_sequence');
      final restore = PodRestore.fromBlob('pump-1', blobWithoutCounters);
      // A fresh EAP sequence is 1; the pod refuses a repeat, so starting low and
      // resyncing is recoverable.
      expect(restore.eapSequence, 1);
      expect(restore.commandSequence, 0);
    });

    test('a missing lifetime falls back to the pod nominal 80 hours', () {
      final restore =
          PodRestore.fromBlob('pump-1', blob()..remove('expiry_hours'));
      expect(restore.expiryHours, 80);
    });

    test('a missing BLE address just means a scan is needed', () {
      final restore =
          PodRestore.fromBlob('pump-1', blob()..remove('ble_address'));
      expect(restore.bleAddress, isNull);
    });

    /// The status snapshot the panel reads is extra, so a blob written before it
    /// existed still restores.
    test('the status snapshot is not required to restore', () {
      final restore = PodRestore.fromBlob('pump-1', blob(overrides: {
        'reservoir_units': 42.5,
        'total_delivered_units': 12.75,
        'last_lifecycle': 'runningAboveMinimumVolume',
      }));
      expect(restore.uniqueId, 4241);
    });
  });

  group('the account copy is caught up without duplicating it', () {
    late Map<String, String> backing;
    late PodStore store;

    setUp(() async {
      backing = <String, String>{};
      store = PodStore(FakeSecureStorage(backing), backing);
    });

    test('a pod already registered is never pushed again', () async {
      await store.savePairing(
        uniqueId: 4241,
        longTermKey: FakeSecureStorage.dummyKey,
        lotNumber: 1,
        podSequenceNumber: 2,
        activatedAt: DateTime(2026, 3, 1),
      );
      await store.saveBackendPumpId('pump-1');

      // Already on file, so nothing is sent and the existing id stands.
      expect(await PumpSync().ensureMirrored(store), isTrue);
      expect(store.backendPumpId, 'pump-1');
    });

    /// With no pod there is nothing to mirror, and asking the account would be a
    /// pointless request on every app start.
    test('an unpaired app mirrors nothing', () async {
      expect(await PumpSync().ensureMirrored(store), isFalse);
      expect(store.backendPumpId, isNull);
    });
  });
}
