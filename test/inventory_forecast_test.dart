import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/inventory/inventory_item.dart';

void main() {
  final now = DateTime(2026, 1, 1);
  int inDays(int days) => now.add(Duration(days: days)).millisecondsSinceEpoch;

  test('run-out date sits at stock / rate', () {
    const item = InventoryItem(id: 'a', name: 's', stock: 10, baseStock: 10, daysPerUnit: 1, anchorMs: 0);
    final out = item.runOutDate(now)!;
    expect(out.difference(now).inDays, 10);
  });

  test('no consumption never runs out', () {
    const item = InventoryItem(id: 'a', name: 's', stock: 5, baseStock: 5, daysPerUnit: 0, anchorMs: 0);
    expect(item.runOutDate(now), isNull);
    expect(item.status(now), StockStatus.ok);
  });

  test('surplus after next delivery follows the plan', () {
    final item = InventoryItem(
      id: 'a',
      name: 's',
      stock: 10,
      baseStock: 30,
      daysPerUnit: 1,
      anchorMs: 0,
      deliveries: [Delivery(atEpochMs: inDays(5), quantity: 20)],
    );
    expect(item.projectedStockBefore(now, item.nextDelivery(now)!.date), 5);
    expect(item.surplusBeforeNextDelivery(now), 5);
    expect(item.status(now), StockStatus.ok);
  });

  test('runs out before delivery is a shortage', () {
    final item = InventoryItem(
      id: 'a',
      name: 's',
      stock: 3,
      baseStock: 10,
      daysPerUnit: 1,
      anchorMs: 0,
      deliveries: [Delivery(atEpochMs: inDays(10), quantity: 20)],
    );
    expect(item.status(now), StockStatus.shortage);
  });

  test('running low without a delivery warns', () {
    const item = InventoryItem(id: 'a', name: 's', stock: 3, baseStock: 10, daysPerUnit: 1, anchorMs: 0);
    expect(item.status(now), StockStatus.low);
  });

  test('non-sensor time decay consumes whole units and advances anchor', () {
    final anchor = now.subtract(const Duration(days: 5));
    final item = InventoryItem(
      id: 'a',
      name: 'pod',
      stock: 5,
      baseStock: 5,
      daysPerUnit: 2,
      type: ItemType.pump,
      anchorMs: anchor.millisecondsSinceEpoch,
    );
    final decayed = item.withTimeDecay(now);
    expect(decayed.stock, 3);
    final advanced = DateTime.fromMillisecondsSinceEpoch(decayed.anchorMs);
    expect(advanced.difference(anchor).inDays, 4);
  });

  test('sensor items are never time-decayed', () {
    final item = InventoryItem(
      id: 'a',
      name: 'g7',
      stock: 5,
      baseStock: 5,
      daysPerUnit: 2,
      type: ItemType.sensor,
      sensorBrand: SensorBrand.dexcom,
      anchorMs: now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
    );
    expect(identical(item.withTimeDecay(now), item), isTrue);
  });
}
