import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/service/advisory_delivery.dart';

import '../../support/secure_storage_mock.dart';

/// Insulin the service gave on its own has to survive until the user has seen
/// it in the app, so the record is storage, not memory.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  test('a delivery is readable until it is dismissed', () async {
    const store = AdvisoryDeliveryStore();
    expect(await store.load(), isNull);
    await store.record(2.5);
    expect((await store.load())!.units, 2.5);
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('the newer delivery replaces the older one', () async {
    const store = AdvisoryDeliveryStore();
    await store.record(1.0);
    await store.record(3.25);
    expect((await store.load())!.units, 3.25);
  });

  test('a malformed or empty record reads as nothing to show', () {
    expect(AdvisoryDelivery.parse(null), isNull);
    expect(AdvisoryDelivery.parse(''), isNull);
    expect(AdvisoryDelivery.parse('2.5'), isNull);
    expect(AdvisoryDelivery.parse('units:now'), isNull);
    expect(AdvisoryDelivery.parse('0.0:1'), isNull);
  });
}
