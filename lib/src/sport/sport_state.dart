import 'package:flutter/foundation.dart';

import 'sport_models.dart';
import 'sport_store.dart';

/// Geteilter Sport-Zustand (Gewichtsverlauf + Schrittlänge), über `main.dart`
/// im Provider-Baum bereitgestellt. Muster wie `ProfileBolusState`: statisches
/// [load], Setter mutieren → [notifyListeners] → persistieren.
class SportState extends ChangeNotifier {
  final SportStore _store;
  final List<WeightEntry> _weights;
  int _strideCm;

  SportState(this._store, this._weights, this._strideCm);

  static Future<SportState> load() async {
    const store = SportStore();
    final weights = await store.loadWeights()
      ..sort((first, second) => first.atEpochMs.compareTo(second.atEpochMs));
    return SportState(store, weights, await store.loadStrideCm());
  }

  /// Gewichte aufsteigend nach Zeit (für den Verlaufs-Chart).
  List<WeightEntry> get weights => List.unmodifiable(_weights);

  WeightEntry? get latestWeight => _weights.isEmpty ? null : _weights.last;

  int get strideCm => _strideCm;

  Future<void> addWeight(double kg, {DateTime? at}) async {
    final entry = WeightEntry(
      atEpochMs: (at ?? DateTime.now()).millisecondsSinceEpoch,
      kg: kg,
    );
    _weights
      ..add(entry)
      ..sort((first, second) => first.atEpochMs.compareTo(second.atEpochMs));
    notifyListeners();
    await _store.saveWeights(_weights);
  }

  /// Fügt importierte Gewichtseinträge hinzu, die noch nicht vorhanden sind
  /// (dedupliziert per Zeitstempel) — für den Google-Health-Import.
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
    _weights.sort((first, second) => first.atEpochMs.compareTo(second.atEpochMs));
    notifyListeners();
    await _store.saveWeights(_weights);
  }

  Future<void> removeWeight(WeightEntry entry) async {
    _weights.remove(entry);
    notifyListeners();
    await _store.saveWeights(_weights);
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
}
