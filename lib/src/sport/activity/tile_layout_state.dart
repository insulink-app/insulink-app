import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A configurable summary box. The first four are always available; the rest
/// come from a connected Google Health (via Health Connect).
enum TodayTile { steps, distance, calories, weight, restingHr, sleep, heartRate, spo2, respiratoryRate }

extension TodayTileInfo on TodayTile {
  /// Whether this tile's data comes from a Google Health (only rendered while one is
  /// connected).
  bool get isGoogleHealth => index >= TodayTile.restingHr.index;
}

/// Shared ordered-visibility model for a personalizable grid of summary boxes —
/// the Sport "Today" grid, the overview boxes, and the nutrition stats. Generic
/// over the tile enum [T]; subclasses supply the storage key + defaults, and the
/// static helpers take the enum's `values` since generic type params can't reach
/// them. Persisted to secure storage AND the synced settings blob (see
/// [ProfileSettings]) so an arrangement survives logout/login.
///
/// [isConditional] tiles keep their slot but are only rendered when the caller
/// passes `includeConditional` (the Sport tab's Google Health tiles, hidden while
/// disconnected).
abstract class TileLayoutState<T extends Enum> extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();

  final List<T> _order;
  final Set<T> _hidden;

  TileLayoutState(this._order, this._hidden);

  /// Secure-storage key (also the key inside the settings blob).
  String get storageKey;

  /// Tiles that keep a slot but only render when the caller opts in (default:
  /// none). Overridden by the Sport layout for its Google Health tiles.
  bool isConditional(T tile) => false;

  List<T> get order => List.unmodifiable(_order);

  bool isVisible(T tile) => !_hidden.contains(tile);

  /// The tiles to render: visible, in order, conditional tiles only when
  /// [includeConditional].
  List<T> visible(bool includeConditional) => [
    for (final tile in _order)
      if (!_hidden.contains(tile) && (!isConditional(tile) || includeConditional))
        tile,
  ];

  Future<void> setVisible(T tile, bool visible) async {
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
  Future<void> moveTile(T from, T to) async {
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

  static String encode<T extends Enum>(List<T> order, Set<T> hidden) {
    return jsonEncode({
      'order': [for (final tile in order) tile.name],
      'hidden': [for (final tile in hidden) tile.name],
    });
  }

  static Future<String?> read(String key) => _storage.read(key: key);

  /// The persisted blob for [key] (or the encoded default), for the settings sync.
  static Future<String> rawFor<T extends Enum>(
    String key,
    List<T> allValues,
    Set<T> defaultHidden,
  ) async {
    return (await _storage.read(key: key)) ?? encode(allValues, defaultHidden);
  }

  /// Parses a stored blob into (order, hidden), appending any tiles the blob is
  /// missing (an older layout) so newly added metrics still get a slot.
  static ({List<T> order, Set<T> hidden}) parse<T extends Enum>(
    String? raw,
    List<T> allValues,
    Set<T> defaultHidden,
  ) {
    if (raw == null) {
      return (order: allValues.toList(), hidden: {...defaultHidden});
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final order = _tiles(map['order'], allValues);
    final hidden = _tiles(map['hidden'], allValues).toSet();
    for (final tile in allValues) {
      if (!order.contains(tile)) {
        order.add(tile);
        if (defaultHidden.contains(tile)) {
          hidden.add(tile);
        }
      }
    }
    return (order: order, hidden: hidden);
  }

  static List<T> _tiles<T extends Enum>(dynamic names, List<T> allValues) {
    if (names is! List) {
      return [];
    }
    return [
      for (final name in names)
        for (final tile in allValues)
          if (tile.name == name) tile,
    ];
  }
}
