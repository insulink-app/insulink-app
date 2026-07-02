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

  SportState(this._store, this._weights, this._strideCm, this._heightCm);

  static Future<SportState> load() async {
    const store = SportStore();
    final weights = await store.loadWeights()
      ..sort((first, second) => first.atEpochMs.compareTo(second.atEpochMs));
    return SportState(
      store,
      weights,
      await store.loadStrideCm(),
      await store.loadHeightCm(),
    );
  }

  /// Weights ascending by time (for the history chart).
  List<WeightEntry> get weights => List.unmodifiable(_weights);

  WeightEntry? get latestWeight => _weights.isEmpty ? null : _weights.last;

  int get strideCm => _strideCm;

  int get heightCm => _heightCm;

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
    await _saveWeights();
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

  /// Persist the weights and queue a backend sync.
  Future<void> _saveWeights() async {
    await _store.saveWeights(_weights);
    SportSync().pushMeasurements();
  }
}
