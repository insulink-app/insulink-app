import 'package:flutter/foundation.dart';

import '../sport_store.dart';
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
    await _store.saveTrainings(_trainings);
  }

  Future<void> removeTraining(String id) async {
    _trainings.removeWhere((training) => training.id == id);
    notifyListeners();
    await _store.saveTrainings(_trainings);
  }
}
