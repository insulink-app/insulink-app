import 'package:flutter/foundation.dart';

import 'sport_models.dart';
import 'sport_store.dart';
import 'sport_sync.dart';

/// Shared sport state (weight history + stride length), provided in the provider
/// tree via `main.dart`. Pattern like `ProfileBolusState`: static [load],
/// setters mutate → [notifyListeners] → persist.
class SportState extends ChangeNotifier {
  final SportStore _store;
  final List<WeightEntry> _weights;
  int _strideCm;
  int _heightCm;
  int _stepsGoal;
  int _distanceGoalM;
  int _caloriesGoal;
  double _weightGoalKg;

  SportState(
    this._store,
    this._weights,
    this._strideCm,
    this._heightCm,
    this._stepsGoal,
    this._distanceGoalM,
    this._caloriesGoal,
    this._weightGoalKg,
  );

  static Future<SportState> load() async {
    const store = SportStore();
    final weights = await store.loadWeights()
      ..sort((first, second) => first.atEpochMs.compareTo(second.atEpochMs));
    return SportState(
      store,
      weights,
      await store.loadStrideCm(),
      await store.loadHeightCm(),
      await store.loadStepsGoal(),
      await store.loadDistanceGoalM(),
      await store.loadCaloriesGoal(),
      await store.loadWeightGoalKg(),
    );
  }

  /// Re-read the store into THIS instance, so a pull that replaced the stored
  /// weights/goals reaches the UI. Reuses [load] and adopts its values rather
  /// than reading the store twice; the provider keeps this instance, so listeners
  /// just rebuild.
  Future<void> reload() async {
    final fresh = await SportState.load();
    _weights
      ..clear()
      ..addAll(fresh._weights);
    _strideCm = fresh._strideCm;
    _heightCm = fresh._heightCm;
    _stepsGoal = fresh._stepsGoal;
    _distanceGoalM = fresh._distanceGoalM;
    _caloriesGoal = fresh._caloriesGoal;
    _weightGoalKg = fresh._weightGoalKg;
    notifyListeners();
  }

  /// Weights ascending by time (for the history chart).
  List<WeightEntry> get weights => List.unmodifiable(_weights);

  WeightEntry? get latestWeight => _weights.isEmpty ? null : _weights.last;

  int get strideCm => _strideCm;

  int get heightCm => _heightCm;

  /// Daily goals: steps, distance (metres) and calories (kcal). Distance is
  /// exposed in km for the tiles' progress bars.
  int get stepsGoal => _stepsGoal;

  double get distanceGoalKm => _distanceGoalM / 1000;

  int get caloriesGoal => _caloriesGoal;

  /// Target weight (kg), drawn as a line on the weight graph.
  double get weightGoalKg => _weightGoalKg;

  /// Body-mass index from the latest weight and the stored height, or null when
  /// no weight has been logged yet.
  double? get bmi {
    final weight = latestWeight;
    if (weight == null || _heightCm <= 0) {
      return null;
    }
    final meters = _heightCm / 100;
    return weight.kg / (meters * meters);
  }

  Future<void> addWeight(double kg, {DateTime? at}) async {
    final entry = WeightEntry(
      atEpochMs: (at ?? DateTime.now()).millisecondsSinceEpoch,
      kg: kg,
    );
    _weights
      ..add(entry)
      ..sort((first, second) => first.atEpochMs.compareTo(second.atEpochMs));
    notifyListeners();
    await _saveWeights();
  }

  /// Replaces an existing entry with a new weight and/or timestamp. If the
  /// timestamp changed, the old server row (keyed by type+time) is deleted, as
  /// the measurements sync only merges — otherwise it would leave an orphan.
  Future<void> editWeight(
    WeightEntry original, {
    required double kg,
    required DateTime at,
  }) async {
    _weights.remove(original);
    final updated = WeightEntry(atEpochMs: at.millisecondsSinceEpoch, kg: kg);
    _weights
      ..add(updated)
      ..sort((first, second) => first.atEpochMs.compareTo(second.atEpochMs));
    notifyListeners();
    await _store.saveWeights(_weights);
    if (updated.atEpochMs != original.atEpochMs) {
      await SportSync().deleteWeight(original);
    }
    SportSync().pushMeasurements();
  }

  /// Adds imported weight entries that aren't present yet (deduplicated by
  /// timestamp) — for the Google Health import.
  Future<void> mergeWeights(List<WeightEntry> entries) async {
    final known = _weights.map((entry) => entry.atEpochMs).toSet();
    var added = false;
    for (final entry in entries) {
      if (known.add(entry.atEpochMs)) {
        _weights.add(entry);
        added = true;
      }
    }
    if (!added) {
      return;
    }
    _weights.sort(
      (first, second) => first.atEpochMs.compareTo(second.atEpochMs),
    );
    notifyListeners();
    await _saveWeights();
  }

  Future<void> removeWeight(WeightEntry entry) async {
    _weights.remove(entry);
    notifyListeners();
    await _store.saveWeights(_weights);
    await SportSync().deleteWeight(entry);
  }

  Future<void> setStrideCm(int cm) async {
    cm = cm.clamp(40, 120);
    if (cm == _strideCm) {
      return;
    }
    _strideCm = cm;
    notifyListeners();
    await _store.saveStrideCm(cm);
  }

  Future<void> setHeightCm(int cm) async {
    cm = cm.clamp(100, 250);
    if (cm == _heightCm) {
      return;
    }
    _heightCm = cm;
    notifyListeners();
    await _store.saveHeightCm(cm);
  }

  Future<void> setStepsGoal(int steps) async {
    steps = steps.clamp(1000, 50000);
    if (steps == _stepsGoal) {
      return;
    }
    _stepsGoal = steps;
    notifyListeners();
    await _store.saveStepsGoal(steps);
  }

  Future<void> setDistanceGoalM(int metres) async {
    metres = metres.clamp(500, 50000);
    if (metres == _distanceGoalM) {
      return;
    }
    _distanceGoalM = metres;
    notifyListeners();
    await _store.saveDistanceGoalM(metres);
  }

  Future<void> setCaloriesGoal(int kcal) async {
    kcal = kcal.clamp(50, 5000);
    if (kcal == _caloriesGoal) {
      return;
    }
    _caloriesGoal = kcal;
    notifyListeners();
    await _store.saveCaloriesGoal(kcal);
  }

  Future<void> setWeightGoalKg(double kg) async {
    kg = kg.clamp(30, 250);
    if (kg == _weightGoalKg) {
      return;
    }
    _weightGoalKg = kg;
    notifyListeners();
    await _store.saveWeightGoalKg(kg);
  }

  /// Persist the weights and queue a backend sync.
  Future<void> _saveWeights() async {
    await _store.saveWeights(_weights);
    SportSync().pushMeasurements();
  }
}
