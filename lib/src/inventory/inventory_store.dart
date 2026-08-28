import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'inventory_item.dart';

/// Local persistence for the inventory: a single JSON array of [InventoryItem]
/// under [itemsKey] in secure storage. The backend mirror lives in its own
/// section — see [InventorySync].
class InventoryStore {
  static const itemsKey = 'inventory.items';

  final FlutterSecureStorage _storage;

  const InventoryStore([this._storage = const FlutterSecureStorage()]);

  Future<List<InventoryItem>> load() async {
    final raw = await _storage.read(key: itemsKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(InventoryItem.fromJson)
        .toList();
  }

  Future<void> save(List<InventoryItem> items) => _storage.write(
    key: itemsKey,
    value: jsonEncode(items.map((item) => item.toJson()).toList()),
  );

  /// Take one pod of [brand] out of stock when a new pod is activated.
  ///
  /// The same rule as [consumeSensor] and for the same reason: an activation is
  /// the one moment a pod becomes newly known, and the backend id stored
  /// alongside it stops a second sync counting it again.
  Future<bool> consumePump(PumpBrand brand) async {
    final items = await load();
    final index = items.indexWhere((item) =>
        item.type == ItemType.pump &&
        item.pumpBrand == brand &&
        item.stock > 0);
    if (index < 0) {
      return false;
    }
    items[index] = items[index].copyWith(stock: items[index].stock - 1);
    await save(items);
    return true;
  }

  /// Take one sensor of [brand] out of stock when a new sensor is paired.
  /// Runs from the foreground-service isolate (no ChangeNotifier, no context),
  /// so it works straight on the store; the caller triggers the backend sync.
  /// Decrements the first matching item with stock left and returns whether it
  /// changed anything (a no-op if none is tracked or all are empty).
  Future<bool> consumeSensor(SensorBrand brand) async {
    final items = await load();
    final index = items.indexWhere((item) =>
        item.type == ItemType.sensor &&
        item.sensorBrand == brand &&
        item.stock > 0);
    if (index < 0) {
      return false;
    }
    items[index] = items[index].copyWith(stock: items[index].stock - 1);
    await save(items);
    return true;
  }
}
