import 'package:flutter/foundation.dart';

import 'nutrition_models.dart';
import 'nutrition_store.dart';

/// Hydration tracking state: the daily goal and today's logged drinks. Pattern
/// like [SportState] — static [load], setters mutate → [notifyListeners] →
/// persist.
class NutritionState extends ChangeNotifier {
  final NutritionStore _store;
  final List<WaterEntry> _entries;
  int _goalMl;

  NutritionState(this._store, this._entries, this._goalMl);

  static Future<NutritionState> load() async {
    const store = NutritionStore();
    return NutritionState(
      store,
      await store.loadEntries(),
      await store.loadGoalMl(),
    );
  }

  /// Daily goal in litres (stored as ml).
  double get goalLitres => _goalMl / 1000;

  /// Drinks logged since local midnight, newest last.
  List<WaterEntry> get todayEntries {
    final since = _midnightMs();
    return _entries.where((entry) => entry.atEpochMs >= since).toList();
  }

  /// Total millilitres drunk today.
  int get todayMl => todayEntries.fold(0, (sum, entry) => sum + entry.ml);

  /// 0..1 progress toward the goal, capped at 1 for the bar.
  double get todayFraction =>
      _goalMl <= 0 ? 0 : (todayMl / _goalMl).clamp(0.0, 1.0);

  int _midnightMs() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  }

  Future<void> addDrink(int ml, String kind) async {
    _entries.add(
      WaterEntry(
        atEpochMs: DateTime.now().millisecondsSinceEpoch,
        ml: ml,
        kind: kind,
      ),
    );
    notifyListeners();
    await _store.saveEntries(_entries);
  }

  Future<void> removeEntry(WaterEntry entry) async {
    _entries.remove(entry);
    notifyListeners();
    await _store.saveEntries(_entries);
  }

  Future<void> setGoalLitres(double litres) async {
    final ml = (litres.clamp(0.5, 10.0) * 1000).round();
    if (ml == _goalMl) {
      return;
    }
    _goalMl = ml;
    notifyListeners();
    await _store.saveGoalMl(ml);
  }
}
