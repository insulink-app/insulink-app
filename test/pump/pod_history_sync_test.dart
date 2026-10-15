import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_history_sync.dart';
import 'package:insulink/src/pump/pod_store.dart';

/// The account merges these by time and never reads them back as insulin, so
/// the wire shape is the whole contract: who asked, whether the pod confirmed,
/// and every time in epoch ms.
void main() {
  final sync = PodHistorySync();
  final at = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  test('a confirmed notification bolus carries its source', () {
    final entries = sync.deliveryEntries([
      PodDelivery(
        at: at,
        units: 1.5,
        kind: PodDeliveryKind.bolus,
        source: PodDeliverySource.notification,
      ),
    ], const []);

    expect(entries.single, {
      'at': 1700000000000,
      'kind': 'bolus',
      'source': 'notification',
      'units': 1.5,
      'confirmed': true,
    });
  });

  test('an unconfirmed bolus is sent as not confirmed', () {
    final entries = sync.deliveryEntries(const [], [
      PodDelivery(at: at, units: 2, kind: PodDeliveryKind.bolus),
    ]);

    expect(entries.single['confirmed'], isFalse);
  });

  test('an activation volume has no source', () {
    final entries = sync.deliveryEntries([
      PodDelivery(at: at, units: 2.6, kind: PodDeliveryKind.prime),
    ], const []);

    expect(entries.single['source'], '');
  });

  test('contact minutes become epoch ms', () {
    expect(sync.contactTimes([28333333]), [1699999980000]);
  });
}
