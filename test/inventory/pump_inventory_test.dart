import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/inventory/inventory_item.dart';
import 'package:insulink/src/inventory/inventory_store.dart';

import '../support/secure_storage_mock.dart';

InventoryItem pod({
  int stock = 3,
  PumpBrand brand = PumpBrand.omnipodDash,
  String id = 'pods',
}) =>
    InventoryItem(
      id: id,
      name: 'Pods',
      stock: stock,
      baseStock: 10,
      daysPerUnit: 3,
      anchorMs: DateTime(2026, 3, 1).millisecondsSinceEpoch,
      type: ItemType.pump,
      pumpBrand: brand,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  group('a pod item restocks the pump', () {
    test('the brand survives a round trip through storage', () {
      final restored = InventoryItem.fromJson(pod().toJson());
      expect(restored.pumpBrand, PumpBrand.omnipodDash);
      expect(restored.type, ItemType.pump);
    });

    test('a DASH pod is rated for three days', () {
      expect(PumpBrand.omnipodDash.typicalDaysPerUnit, 3);
    });

    /// The eight hours of grace are deliberately not counted: stock planning
    /// should assume the pod is replaced on schedule, not run into its reserve.
    test('an unknown pump has no figure, so the user gives one', () {
      expect(PumpBrand.other.typicalDaysPerUnit, isNull);
    });

    test('activating a pod takes one out of stock', () async {
      const store = InventoryStore();
      await store.save([pod(stock: 3)]);

      expect(await store.consumePump(PumpBrand.omnipodDash), isTrue);
      expect((await store.load()).single.stock, 2);
    });

    test('an empty item is left alone rather than driven negative', () async {
      const store = InventoryStore();
      await store.save([pod(stock: 0)]);

      expect(await store.consumePump(PumpBrand.omnipodDash), isFalse);
      expect((await store.load()).single.stock, 0);
    });

    test('a pump nobody tracks changes nothing', () async {
      const store = InventoryStore();
      await store.save([]);

      expect(await store.consumePump(PumpBrand.omnipodDash), isFalse);
    });

    test('only the matching brand is touched', () async {
      const store = InventoryStore();
      await store.save([pod(brand: PumpBrand.other, id: 'other-pump')]);

      expect(await store.consumePump(PumpBrand.omnipodDash), isFalse);
      expect((await store.load()).single.stock, 3);
    });
  });

  group('a pod is counted once, not twice', () {
    /// It leaves stock when the pod is activated. Counting elapsed time as well
    /// would take a second unit out for the same piece of hardware.
    test('a tracked pod does not also decay with time', () {
      final item = pod(stock: 3);
      expect(item.isConsumedOnPairing, isTrue);

      final later = item.withTimeDecay(DateTime(2026, 3, 20));

      expect(later.stock, 3);
    });

    /// A pump the app cannot pair gets no automatic decrement, so the time
    /// estimate is the only thing it has.
    test('an untracked pump still decays with time', () {
      final item = pod(stock: 3, brand: PumpBrand.other);
      expect(item.isConsumedOnPairing, isFalse);

      final later = item.withTimeDecay(DateTime(2026, 3, 10));

      expect(later.stock, lessThan(3));
    });
  });
}
