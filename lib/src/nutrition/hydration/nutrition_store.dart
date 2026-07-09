import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'nutrition_models.dart';

/// Persistence for the hydration tracker: the daily goal (ml) and the logged
/// drinks. Same shape as [SportStore] — plain JSON blobs in secure storage,
/// loaded once into the [NutritionState] ChangeNotifier.
class NutritionStore {
  /// Storage key for the daily goal — public so [ProfileSettings] can sync it to
  /// the backend and write the server's value straight back here.
  static const goalKey = 'nutrition.water_goal_ml';
  static const _kGoal = goalKey;
  static const _kEntries = 'nutrition.water_entries';
  static const _entryCap = 500;

  /// Default daily goal: 2 L.
  static const defGoalMl = 2000;

  final FlutterSecureStorage _storage;

  const NutritionStore([this._storage = const FlutterSecureStorage()]);

  Future<int> loadGoalMl() async =>
      int.tryParse(await _storage.read(key: _kGoal) ?? '') ?? defGoalMl;

  Future<void> saveGoalMl(int ml) => _storage.write(key: _kGoal, value: '$ml');

  Future<List<WaterEntry>> loadEntries() async {
    final raw = await _storage.read(key: _kEntries);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(WaterEntry.fromJson)
        .toList();
  }

  /// Persist the entries, capped to the most recent [_entryCap].
  Future<void> saveEntries(List<WaterEntry> entries) {
    final capped = entries.length > _entryCap
        ? entries.sublist(entries.length - _entryCap)
        : entries;
    return _storage.write(
      key: _kEntries,
      value: jsonEncode(capped.map((entry) => entry.toJson()).toList()),
    );
  }
}
