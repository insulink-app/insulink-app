import 'package:flutter/foundation.dart';

import 'inventory_item.dart';
import 'inventory_store.dart';
import 'inventory_sync.dart';

/// Inventory state: the tracked supplies. Mutations persist locally AND sync to
/// the account (via [InventorySync], its own backend section) so a second
/// device / re-login adopts the same inventory.
class InventoryState extends ChangeNotifier {
  final InventoryStore _store;
  final List<InventoryItem> _items;

  InventoryState(this._store, this._items);

  static Future<InventoryState> load() async {
    const store = InventoryStore();
    final state = InventoryState(store, await store.load());
    await state._applyTimeDecay();
    return state;
  }

  /// Re-read the store into THIS instance. The service isolate can decrement
  /// stock in the background (a new sensor auto-consumes one), which the UI's
  /// in-memory list can't see; the inventory page calls this on open so it
  /// shows the current stock. Elapsed-time consumption is applied here too.
  Future<void> refresh() async {
    final fresh = await _store.load();
    _items
      ..clear()
      ..addAll(fresh);
    await _applyTimeDecay();
    notifyListeners();
  }

  /// Consume whole units for the time elapsed on non-sensor items (see
  /// [InventoryItem.withTimeDecay]) and persist if anything changed. Called on
  /// every load/refresh, so a unit ticks off the next time the app is opened.
  Future<void> _applyTimeDecay() async {
    final now = DateTime.now();
    var changed = false;
    for (var index = 0; index < _items.length; index++) {
      final decayed = _items[index].withTimeDecay(now);
      if (!identical(decayed, _items[index])) {
        _items[index] = decayed;
        changed = true;
      }
    }
    if (changed) {
      await _store.save(_items);
      InventorySync().push();
    }
  }

  List<InventoryItem> get items => List.unmodifiable(_items);

  bool get hasWarning {
    final now = DateTime.now();
    return _items.any((item) => item.status(now) != StockStatus.ok);
  }

  /// Insert a new item or replace the one with the same id.
  Future<void> addOrUpdate(InventoryItem item) async {
    final index = _items.indexWhere((existing) => existing.id == item.id);
    if (index >= 0) {
      _items[index] = item;
    } else {
      _items.add(item);
    }
    await _persist();
  }

  /// Set an item's current stock (from the card's +/- buttons or input),
  /// clamped at zero. Resets the decay anchor: the user just declared what is
  /// on hand now, so elapsed-time consumption restarts from this moment.
  Future<void> setStock(String id, int stock) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) {
      return;
    }
    _items[index] = _items[index].copyWith(
      stock: stock < 0 ? 0 : stock,
      anchorMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _persist();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((item) => item.id == id);
    await _persist();
  }

  /// Move the item at [oldIndex] to [newIndex] (drag-reorder). [newIndex] is
  /// already post-removal adjusted (ReorderableListView's onReorderItem). The
  /// new order is the stored order: [_persist] saves the reordered array locally
  /// AND pushes it via [InventorySync], so the backend mirror adopts the same
  /// sequence.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final moved = _items.removeAt(oldIndex);
    _items.insert(newIndex, moved);
    await _persist();
  }

  Future<void> _persist() async {
    notifyListeners();
    await _store.save(_items);
    InventorySync().push();
  }
}
