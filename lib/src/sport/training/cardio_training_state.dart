import 'package:flutter/foundation.dart';

import '../sport_store.dart';
import '../sport_sync.dart';
import 'cardio_detector.dart';
import 'cardio_models.dart';

/// Shared state of the endurance trainings: the stored [CardioTraining]s.
/// Pattern like [SportState]: static [load], mutator persists →
/// [notifyListeners]. The live recording itself is owned by the recording page
/// via its own `CardioTracker`.
class CardioTrainingState extends ChangeNotifier {
  final SportStore _store;
  final List<CardioTraining> _trainings;

  CardioTrainingState(this._store, this._trainings);

  static Future<CardioTrainingState> load() async {
    const store = SportStore();
    final trainings = await store.loadTrainings()
      ..sort((first, second) => first.startMs.compareTo(second.startMs));
    return CardioTrainingState(store, trainings);
  }

  /// Trainings ascending by start time.
  List<CardioTraining> get trainings => List.unmodifiable(_trainings);

  Future<void> addTraining(CardioTraining training) async {
    _trainings.add(training);
    notifyListeners();
    await _saveTrainings();
  }

  Future<void> removeTraining(String id) async {
    _trainings.removeWhere((training) => training.id == id);
    notifyListeners();
    await _saveTrainings();
  }

  /// Scans the background GPS log for endurance trainings and saves new ones
  /// directly (marked as auto-detected). Runs over points added since the last
  /// scan (watermark), skips anything overlapping an existing training. Called
  /// on opening the sport tab. `ponytail:` the watermark advances to the newest
  /// point, so a training still in progress at scan time is finalised early;
  /// acceptable for a page-open scan, revisit if live detection is wanted.
  Future<void> detectFromLog() async {
    final log = await _store.loadLocationLog();
    if (log.isEmpty) {
      return;
    }
    final watermark = await _store.loadDetectWatermark();
    final fresh = watermark == null
        ? log
        : [for (final point in log) if (point.tMs > watermark) point];
    await _store.saveDetectWatermark(log.last.tMs);
    var changed = false;
    for (final training in const CardioDetector().detect(fresh)) {
      if (_overlapsExisting(training)) {
        continue;
      }
      _trainings.add(training);
      changed = true;
    }
    if (!changed) {
      return;
    }
    _trainings.sort((first, second) => first.startMs.compareTo(second.startMs));
    notifyListeners();
    await _saveTrainings();
  }

  bool _overlapsExisting(CardioTraining candidate) {
    for (final existing in _trainings) {
      if (candidate.startMs <= existing.endMs &&
          existing.startMs <= candidate.endMs) {
        return true;
      }
    }
    return false;
  }

  /// Persist the trainings and queue a backend sync.
  Future<void> _saveTrainings() async {
    await _store.saveTrainings(_trainings);
    SportSync().pushTrainings();
  }
}
