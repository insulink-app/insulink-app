import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_account_history.dart';
import 'package:insulink/src/pump/pod_log_entry.dart';
import 'package:insulink/src/pump/pod_store.dart';

import 'fake_secure_storage.dart';

/// After a reinstall the phone's pump log is empty; the account's copy fills
/// it back in without counting anything the phone still has twice.
void main() {
  late Map<String, String> backing;
  late PodStore store;
  final bolusAt = DateTime(2026, 3, 1, 13, 30);

  setUp(() {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  final account = PodAccountHistory(
    deliveries: [
      PodDelivery(at: bolusAt, units: 4, kind: PodDeliveryKind.bolus),
      PodDelivery(
        at: DateTime(2026, 3, 1, 13, 40),
        units: 0.1,
        kind: PodDeliveryKind.microBolus,
      ),
    ],
    basalSamples: [
      (at: DateTime(2026, 3, 1, 13, 0), units: 0.2),
      (at: DateTime(2026, 3, 1, 13, 15), units: 0.2),
    ],
  );

  test('an empty phone rebuilds bolus, micro bolus and basal', () {
    final timeline = PodLogEntry.timeline(store, account);

    expect(timeline.map((entry) => entry.labelKey), [
      'pump.log.kind.micro_bolus',
      'pump.log.kind.bolus',
      'pump.log.kind.basal',
    ]);
    expect(timeline.last.units, closeTo(0.4, 1e-9));
    expect(account.basalTotal(store), closeTo(0.4, 1e-9));
    expect(account.microBolusTotal(store), closeTo(0.1, 1e-9));
  });

  test('a delivery both sides know is listed once, as the phone has it', () async {
    await store.recordDelivery(
      PodDelivery(at: bolusAt, units: 2.5, kind: PodDeliveryKind.bolus),
    );

    final boluses = account
        .mergedDeliveries(store)
        .where((entry) => entry.kind == PodDeliveryKind.bolus);

    expect(boluses.single.units, 2.5);
  });
}
