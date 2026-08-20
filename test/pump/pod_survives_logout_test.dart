import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_store.dart';

import 'fake_secure_storage.dart';

/// A pod must survive signing out.
///
/// Everything else a logout wipes comes back: glucose and settings from the
/// account, a sensor by re-pairing. A pod cannot. It answers only the controller
/// that activated it, once, for good, so its key is the one piece of local state
/// whose loss cannot be undone — and a pod on the body with no key keeps
/// delivering insulin with nothing able to stop it.
///
/// The guard is a key prefix, so this checks the prefix actually covers every
/// key the store writes. A future key without it would be wiped silently.
void main() {
  /// Mirrors `ProfileAccount._podPrefix`.
  const podPrefix = 'pod.';

  test('every key a paired pod writes carries the protected prefix', () async {
    final backing = <String, String>{};
    final store = PodStore(FakeSecureStorage(backing), backing);

    await store.savePairing(
      uniqueId: 4241,
      longTermKey: FakeSecureStorage.dummyKey,
      lotNumber: 1,
      podSequenceNumber: 2,
      activatedAt: DateTime(2026, 3, 1),
      expiryHours: 80,
      resetSessionCounters: true,
    );
    await store.saveBleAddress('AA:BB:CC:DD:EE:FF');
    await store.saveActivationStep('running');
    await store.saveActivationFacts('{}');
    await store.saveBackendPumpId('pump-1');
    await store.saveBackendSyncedData('{}');
    await store.saveMessageSequence(39);
    await store.markSeen(DateTime(2026, 3, 1));
    await store.setSuspendedByUs(false);
    await store.saveBasalRates(List<double>.filled(24, 0.8));
    await store.startBasalAccounting(DateTime(2026, 3, 1));
    await store.recordDelivery(PodDelivery(
      at: DateTime(2026, 3, 1),
      units: 1.0,
      kind: PodDeliveryKind.bolus,
    ));

    expect(backing, isNotEmpty);
    final unprotected =
        backing.keys.where((key) => !key.startsWith(podPrefix)).toList();
    expect(
      unprotected,
      isEmpty,
      reason: 'these pod keys would be wiped by a logout: $unprotected',
    );
  });
}
