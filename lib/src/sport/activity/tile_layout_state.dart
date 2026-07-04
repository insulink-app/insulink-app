import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A configurable summary box. The first four are always available; the rest
/// come from a connected Fitbit (via Health Connect).
enum TodayTile { steps, distance, calories, weight, restingHr, sleep, heartRate, spo2 }

extension TodayTileInfo on TodayTile {
  /// Whether this tile's data comes from a Fitbit (only rendered while one is
  /// connected).
  bool get isFitbit => index >= TodayTile.restingHr.index;
}

/// Shared ordered-visibility model for a personalizable grid of summary boxes —
/// the Sport "Today" grid and the overview boxes. Subclasses only supply the
/// storage key + defaults; all order/visibility/persistence logic lives here.
/// Persisted to secure storage AND the synced settings blob (see
/// [ProfileSettings]) so an arrangement survives logout/login. Fitbit tiles keep
/// their slot even while disconnected; they are just not rendered.
abstract class TileLayoutState extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();

  final List<TodayTile> _order;
  final Set<TodayTile> _hidden;

  TileLayoutState(this._order, this._hidden);

  /// Secure-storage key (also the key inside the settings blob).
  String get storageKey;

  List<TodayTile> get order => List.unmodifiable(_order);

  bool isVisible(TodayTile tile) => !_hidden.contains(tile);

  /// The tiles to render: visible, in order, Fitbit tiles only when connected.
  List<TodayTile> visible(bool fitbitConnected) => [
    for (final tile in _order)
      if (!_hidden.contains(tile) && (!tile.isFitbit || fitbitConnected)) tile,
  ];

  Future<void> setVisible(TodayTile tile, bool visible) async {
    if (visible) {
      _hidden.remove(tile);
    } else {
      _hidden.add(tile);
    }
    notifyListeners();
    await _save();
  }

  /// [newIndex] is already adjusted for the removal at [oldIndex] (the
  /// `onReorderItem` contract) — used by the editor's reorderable list.
  Future<void> reorder(int oldIndex, int newIndex) async {
    _order.insert(newIndex, _order.removeAt(oldIndex));
    notifyListeners();
    await _save();
  }

  /// Moves [from] to just before [to] — the drag-and-drop reorder on the grid.
  Future<void> moveTile(TodayTile from, TodayTile to) async {
    if (from == to) {
      return;
    }
    _order.remove(from);
    final index = _order.indexOf(to);
    _order.insert(index < 0 ? _order.length : index, from);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    await _storage.write(key: storageKey, value: encode(_order, _hidden));
  }

  static String encode(List<TodayTile> order, Set<TodayTile> hidden) {
    return jsonEncode({
      'order': [for (final tile in order) tile.name],
      'hidden': [for (final tile in hidden) tile.name],
    });
  }

  static Future<String?> read(String key) => _storage.read(key: key);

  /// The persisted blob for [key] (or the encoded default), for the settings sync.
  static Future<String> rawFor(String key, Set<TodayTile> defaultHidden) async {
    return (await _storage.read(key: key)) ??
        encode(TodayTile.values.toList(), defaultHidden);
  }

  /// Parses a stored blob into (order, hidden), appending any tiles the blob is
  /// missing (an older layout) so newly added metrics still get a slot.
  static ({List<TodayTile> order, Set<TodayTile> hidden}) parse(
    String? raw,
    Set<TodayTile> defaultHidden,
  ) {
    if (raw == null) {
      return (order: TodayTile.values.toList(), hidden: {...defaultHidden});
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final order = _tiles(map['order']);
    final hidden = _tiles(map['hidden']).toSet();
    for (final tile in TodayTile.values) {
      if (!order.contains(tile)) {
        order.add(tile);
        if (defaultHidden.contains(tile)) {
          hidden.add(tile);
        }
      }
    }
    return (order: order, hidden: hidden);
  }

  static List<TodayTile> _tiles(dynamic names) {
    if (names is! List) {
      return [];
    }
    return [
      for (final name in names)
        for (final tile in TodayTile.values)
          if (tile.name == name) tile,
    ];
  }
}
