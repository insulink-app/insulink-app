import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/inventory/inventory_item.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  test('wire keys round-trip, unknown falls back', () {
    expect(ItemType.fromWireKey('sensor'), ItemType.sensor);
    expect(ItemType.fromWireKey('nonsense'), ItemType.other);
    expect(ItemType.fromWireKey(null), ItemType.other);
    expect(SensorBrand.fromWireKey('libre'), SensorBrand.libre);
    expect(SensorBrand.fromWireKey('nonsense'), SensorBrand.other);
    expect(SensorBrand.fromWireKey(null), isNull);
  });

  test('typical per-unit days are known for the two supported CGMs', () {
    expect(SensorBrand.libre.typicalDaysPerUnit, 14);
    expect(SensorBrand.dexcom.typicalDaysPerUnit, 10);
    expect(SensorBrand.other.typicalDaysPerUnit, isNull);
  });

  test('json round-trip keeps every field', () {
    final item = InventoryItem(
      id: 'a',
      name: 'Pods',
      stock: 7,
      baseStock: 20,
      daysPerUnit: 3,
      anchorMs: 1000,
      type: ItemType.pump,
      sensorBrand: SensorBrand.dexcom,
      deliveries: const [Delivery(atEpochMs: 42, quantity: 5)],
    );

    final restored = InventoryItem.fromJson(item.toJson());

    expect(restored.id, 'a');
    expect(restored.name, 'Pods');
    expect(restored.stock, 7);
    expect(restored.baseStock, 20);
    expect(restored.daysPerUnit, 3);
    expect(restored.anchorMs, 1000);
    expect(restored.type, ItemType.pump);
    expect(restored.sensorBrand, SensorBrand.dexcom);
    expect(restored.deliveries.single.quantity, 5);
    expect(restored.deliveries.single.date.millisecondsSinceEpoch, 42);
  });

  test('a legacy json without base_stock uses the stock as the base', () {
    final restored = InventoryItem.fromJson({
      'id': 'a',
      'name': 'Old',
      'stock': 4,
    });

    expect(restored.baseStock, 4);
    expect(restored.daysPerUnit, 0);
    expect(restored.type, ItemType.other);
    expect(restored.sensorBrand, isNull);
    expect(restored.deliveries, isEmpty);
  });

  test('stock fraction is clamped to the bar range', () {
    const empty = InventoryItem(
      id: 'a', name: 'x', stock: 0, baseStock: 0, daysPerUnit: 0, anchorMs: 0);
    const over = InventoryItem(
      id: 'a', name: 'x', stock: 30, baseStock: 20, daysPerUnit: 0, anchorMs: 0);
    const half = InventoryItem(
      id: 'a', name: 'x', stock: 5, baseStock: 10, daysPerUnit: 0, anchorMs: 0);

    expect(empty.stockFraction, 0);
    expect(over.stockFraction, 1);
    expect(half.stockFraction, 0.5);
  });

  test('time decay consumes whole units and advances the anchor', () {
    final item = InventoryItem(
      id: 'a',
      name: 'Pods',
      stock: 10,
      baseStock: 10,
      daysPerUnit: 3,
      anchorMs: now.millisecondsSinceEpoch,
    );

    final decayed = item.withTimeDecay(now.add(const Duration(days: 7)));

    expect(decayed.stock, 8);
    expect(
      decayed.anchorMs,
      now.add(const Duration(days: 6)).millisecondsSinceEpoch,
    );
  });

  test('time decay is a no-op for sensors, no rate, or nothing due yet', () {
    final anchor = now.millisecondsSinceEpoch;
    final sensor = InventoryItem(
      id: 'a', name: 'x', stock: 5, baseStock: 5, daysPerUnit: 10,
      anchorMs: anchor, type: ItemType.sensor);
    final untimed = InventoryItem(
      id: 'a', name: 'x', stock: 5, baseStock: 5, daysPerUnit: 0,
      anchorMs: anchor);
    final tooSoon = InventoryItem(
      id: 'a', name: 'x', stock: 5, baseStock: 5, daysPerUnit: 3,
      anchorMs: anchor);
    final later = now.add(const Duration(days: 30));

    expect(sensor.withTimeDecay(later), same(sensor));
    expect(untimed.withTimeDecay(later), same(untimed));
    expect(tooSoon.withTimeDecay(now.add(const Duration(days: 2))), same(tooSoon));
  });

  test('time decay never drives the stock below zero', () {
    final item = InventoryItem(
      id: 'a',
      name: 'x',
      stock: 2,
      baseStock: 10,
      daysPerUnit: 1,
      anchorMs: now.millisecondsSinceEpoch,
    );

    expect(item.withTimeDecay(now.add(const Duration(days: 99))).stock, 0);
  });
}
