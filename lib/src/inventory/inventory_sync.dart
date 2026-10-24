import 'dart:async';
import 'package:insulink/src/request/response_json.dart';

import 'package:flutter/widgets.dart';

import '../request/request.dart';
import '../request/sync_ledger.dart';
import 'inventory_item.dart';
import 'inventory_store.dart';

/// Mirrors the user's inventory to their backend account and pulls it back on
/// sign-in. Same shape as [NutritionSync], one collection: [push] debounces a
/// best-effort replace-all POST; [pull] runs on sign-in / cold start and writes
/// the account's items into the store before the provider tree reloads.
///
/// The static timer/flag are per-isolate, which is exactly right: the UI isolate
/// and the foreground-service isolate (a new sensor auto-consumes one there)
/// each debounce their own writes.
class InventorySync {
  static const _store = InventoryStore();
  static const _ledger = SyncLedger();
  static const _ledgerKey = 'inventory.items';
  static Timer? _timer;

  /// True while a local change has not reached the backend yet — the debounce is
  /// armed or its POST is in flight. Guards [pull] from clobbering it.
  static bool _unsent = false;

  /// Queue a replace-all push of the current store (debounced 3 s). The
  /// [SyncLedger] mark stays until the account accepts it, so a failed push is
  /// merged on the next pull instead of reverted.
  void push() {
    _timer?.cancel();
    _unsent = true;
    unawaited(_ledger.mark(_ledgerKey));
    _timer = Timer(const Duration(seconds: 3), () async {
      try {
        if (await _send()) {
          await _ledger.clear(_ledgerKey);
        }
      } finally {
        _unsent = false;
      }
    });
  }

  Future<bool> _send() async {
    final items = await _store.load();
    final response = await Request.post(
      url: '/inventory/items/sync/',
      body: {'items': items.map((item) => item.toJson()).toList()},
    ).send(null);
    return response.isApiSuccess;
  }

  /// Adopt the account's inventory into the local store (sign-in + cold start),
  /// unless a local change is still queued ([_unsent] — the server never saw it).
  ///
  /// Merged by id, never by content: keyed by the whole JSON, an item edited
  /// locally (stock 5) and its older account copy (stock 4) counted as two
  /// items, and the stale copy was appended as a duplicate whose +/- buttons
  /// changed the first item with that id instead of itself.
  Future<void> pull(BuildContext? context) async {
    final response = await Request.get(
      url: '/inventory/items/find/',
    ).send(context);
    if (_unsent) {
      return;
    }
    final body = response.jsonObject;
    if (body == null) {
      return;
    }
    if (body['success'] != true || body['items'] is! List) {
      return;
    }
    final merged = await _ledger.adopt(
      collection: _ledgerKey,
      remote: [
        for (final item in body['items'] as List)
          InventoryItem.fromJson((item as Map).cast()),
      ],
      local: _store.load,
      save: _store.save,
      keyOf: (item) => item.id,
    );
    if (merged) {
      push();
    }
  }
}
