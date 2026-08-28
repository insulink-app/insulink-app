import 'dart:async';
import 'package:insulink/src/request/response_json.dart';

import 'package:flutter/widgets.dart';

import '../request/request.dart';
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
  static Timer? _timer;

  /// True while a local change has not reached the backend yet — the debounce is
  /// armed or its POST is in flight. Guards [pull] from clobbering it.
  static bool _unsent = false;

  /// Queue a replace-all push of the current store (debounced 3 s).
  void push() {
    _timer?.cancel();
    _unsent = true;
    _timer = Timer(const Duration(seconds: 3), () async {
      try {
        await _send();
      } finally {
        _unsent = false;
      }
    });
  }

  Future<void> _send() async {
    final items = await _store.load();
    await Request.post(
      url: '/inventory/items/sync/',
      body: {'items': items.map((item) => item.toJson()).toList()},
    ).send(null);
  }

  /// Adopt the account's inventory into the local store (sign-in + cold start),
  /// unless a local change is still queued ([_unsent] — the server never saw it).
  Future<void> pull(BuildContext? context) async {
    final response = await Request.get(url: '/inventory/items/find/').send(context);
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
    await _store.save([
      for (final item in body['items'] as List)
        InventoryItem.fromJson((item as Map).cast()),
    ]);
  }
}
