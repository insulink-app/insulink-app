import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/inventory/inventory_item.dart';
import 'package:insulink/src/inventory/inventory_state.dart';
import 'package:insulink/src/inventory/inventory_store.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> backing;

  setUp(() {
    backing = installSecureStorageMock();
  });

  InventoryItem item(
    String id, {
    int stock = 10,
    double daysPerUnit = 0,
    ItemType type = ItemType.other,
    int? anchorMs,
    List<Delivery> deliveries = const [],
  }) => InventoryItem(
    id: id,
    name: id,
    stock: stock,
    baseStock: 20,
    daysPerUnit: daysPerUnit,
    anchorMs: anchorMs ?? DateTime.now().millisecondsSinceEpoch,
    type: type,
    deliveries: deliveries,
  );

  test('a fresh state is empty and warns about nothing', () async {
    final state = await InventoryState.load();

    expect(state.items, isEmpty);
    expect(state.hasWarning, isFalse);
  });

  test('addOrUpdate inserts a new item and replaces one with the same id', () async {
    final state = await InventoryState.load();

    await state.addOrUpdate(item('pods', stock: 5));
    await state.addOrUpdate(item('sensors', stock: 3));
    await state.addOrUpdate(item('pods', stock: 8));

    expect(state.items.length, 2);
    expect(state.items.first.stock, 8);
  });

  test('setStock clamps at zero and resets the decay anchor', () async {
    final state = await InventoryState.load();
    await state.addOrUpdate(item('pods', stock: 5, anchorMs: 0));

    await state.setStock('pods', -3);

    expect(state.items.single.stock, 0);
    expect(state.items.single.anchorMs, greaterThan(0));
  });

  test('setStock on an unknown id is a no-op', () async {
    final state = await InventoryState.load();
    await state.addOrUpdate(item('pods', stock: 5));

    await state.setStock('gone', 99);

    expect(state.items.single.stock, 5);
  });

  test('removing an item persists the shorter list', () async {
    final state = await InventoryState.load();
    await state.addOrUpdate(item('pods'));
    await state.addOrUpdate(item('sensors'));

    await state.remove('pods');
    await state.refresh();

    expect(state.items.single.id, 'sensors');
  });

  test('reorder stores the new sequence', () async {
    final state = await InventoryState.load();
    await state.addOrUpdate(item('a'));
    await state.addOrUpdate(item('b'));
    await state.addOrUpdate(item('c'));

    await state.reorder(0, 2);
    await state.refresh();

    expect(state.items.map((entry) => entry.id), ['b', 'c', 'a']);
  });

  test('hasWarning fires once an item runs out before its delivery', () async {
    final state = await InventoryState.load();
    await state.addOrUpdate(item('calm', stock: 10));
    expect(state.hasWarning, isFalse);

    await state.addOrUpdate(item('short', stock: 2, daysPerUnit: 1));
    expect(state.hasWarning, isTrue);
  });

  test('loading applies the elapsed-time consumption and persists it', () async {
    final anchor = DateTime.now()
        .subtract(const Duration(days: 9))
        .millisecondsSinceEpoch;
    backing['inventory.items'] = jsonEncode([
      item('pods', stock: 10, daysPerUnit: 3, anchorMs: anchor).toJson(),
    ]);

    final state = await InventoryState.load();

    expect(state.items.single.stock, 7);
    final stored = (jsonDecode(backing['inventory.items']!) as List).single;
    expect(stored['stock'], 7, reason: 'the decay is written back');
  });

  test('sensors are never consumed by elapsed time', () async {
    final anchor = DateTime.now()
        .subtract(const Duration(days: 90))
        .millisecondsSinceEpoch;
    backing['inventory.items'] = jsonEncode([
      item(
        'g7',
        stock: 4,
        daysPerUnit: 10,
        type: ItemType.sensor,
        anchorMs: anchor,
      ).toJson(),
    ]);

    final state = await InventoryState.load();

    expect(state.items.single.stock, 4);
  });

  test('refresh adopts a stock the background isolate wrote', () async {
    final state = await InventoryState.load();
    await state.addOrUpdate(item('g7', stock: 4, type: ItemType.sensor));

    backing['inventory.items'] = jsonEncode([
      item('g7', stock: 3, type: ItemType.sensor).toJson(),
    ]);
    await state.refresh();

    expect(state.items.single.stock, 3);
  });

  test('pairing a sensor consumes one unit of the matching brand', () async {
    const store = InventoryStore();
    await store.save([
      InventoryItem(
        id: 'g7',
        name: 'G7',
        stock: 4,
        baseStock: 10,
        daysPerUnit: 10,
        anchorMs: 0,
        type: ItemType.sensor,
        sensorBrand: SensorBrand.dexcom,
      ),
    ]);

    expect(await store.consumeSensor(SensorBrand.dexcom), isTrue);
    expect((await store.load()).single.stock, 3);

    expect(
      await store.consumeSensor(SensorBrand.libre),
      isFalse,
      reason: 'another brand is not tracked',
    );
  });

  test('consuming from an empty or untracked stock changes nothing', () async {
    const store = InventoryStore();
    await store.save([
      InventoryItem(
        id: 'g7',
        name: 'G7',
        stock: 0,
        baseStock: 10,
        daysPerUnit: 10,
        anchorMs: 0,
        type: ItemType.sensor,
        sensorBrand: SensorBrand.dexcom,
      ),
    ]);

    expect(await store.consumeSensor(SensorBrand.dexcom), isFalse);
    expect((await store.load()).single.stock, 0);
  });

  test('the item list is unmodifiable from the outside', () async {
    final state = await InventoryState.load();

    expect(() => state.items.add(item('x')), throwsUnsupportedError);
  });
}
