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
  int _carbsGoalG;
  int _proteinGoalG;

  NutritionState(
    this._store,
    this._entries,
    this._goalMl,
    this._carbsGoalG,
    this._proteinGoalG,
  );

  static Future<NutritionState> load() async {
    const store = NutritionStore();
    return NutritionState(
      store,
      await store.loadEntries(),
      await store.loadGoalMl(),
      await store.loadCarbsGoalG(),
      await store.loadProteinGoalG(),
    );
  }

  /// Daily goal in litres (stored as ml).
  double get goalLitres => _goalMl / 1000;

  /// Daily carb goal in grams.
  int get carbsGoalG => _carbsGoalG;

  /// Daily protein goal in grams.
  int get proteinGoalG => _proteinGoalG;

  /// All logged drinks (for the water history/detail page).
  List<WaterEntry> get entries => List.unmodifiable(_entries);

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

  Future<void> setCarbsGoalG(double grams) async {
    final rounded = grams.clamp(20, 800).round();
    if (rounded == _carbsGoalG) {
      return;
    }
    _carbsGoalG = rounded;
    notifyListeners();
    await _store.saveCarbsGoalG(rounded);
  }

  Future<void> setProteinGoalG(double grams) async {
    final rounded = grams.clamp(10, 400).round();
    if (rounded == _proteinGoalG) {
      return;
    }
    _proteinGoalG = rounded;
    notifyListeners();
    await _store.saveProteinGoalG(rounded);
  }
}
