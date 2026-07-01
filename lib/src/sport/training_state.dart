import 'package:flutter/foundation.dart';

import 'sport_models.dart';
import 'sport_store.dart';

/// Shared training state: exercise library, routines and logged sessions. Its
/// own [ChangeNotifier] alongside [SportState] (weight) so both files stay
/// focused. Pattern: static [load], mutators mutate → [notifyListeners] →
/// persist.
class TrainingState extends ChangeNotifier {
  final SportStore _store;
  final List<SportExercise> _exercises;
  final List<SportRoutine> _routines;
  final List<WorkoutSession> _sessions;

  TrainingState(this._store, this._exercises, this._routines, this._sessions);

  static Future<TrainingState> load() async {
    const store = SportStore();
    return TrainingState(
      store,
      await store.loadExercises(),
      await store.loadRoutines(),
      await store.loadSessions(),
    );
  }

  List<SportExercise> get exercises => List.unmodifiable(_exercises);
  List<SportRoutine> get routines => List.unmodifiable(_routines);
  List<WorkoutSession> get sessions => List.unmodifiable(_sessions);

  SportExercise? exerciseById(String id) {
    for (final exercise in _exercises) {
      if (exercise.id == id) {
        return exercise;
      }
    }
    return null;
  }

  SportRoutine? routineById(String id) {
    for (final routine in _routines) {
      if (routine.id == id) {
        return routine;
      }
    }
    return null;
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  // ---- Exercises ----

  Future<SportExercise> addExercise(String name, ExerciseKind kind) async {
    final exercise = SportExercise(id: _newId(), name: name, kind: kind);
    _exercises.add(exercise);
    notifyListeners();
    await _store.saveExercises(_exercises);
    return exercise;
  }

  Future<void> updateExercise(SportExercise exercise) async {
    final index = _exercises.indexWhere((other) => other.id == exercise.id);
    if (index < 0) {
      return;
    }
    _exercises[index] = exercise;
    notifyListeners();
    await _store.saveExercises(_exercises);
  }

  Future<void> removeExercise(String id) async {
    _exercises.removeWhere((exercise) => exercise.id == id);
    notifyListeners();
    await _store.saveExercises(_exercises);
  }

  // ---- Routines ----

  Future<SportRoutine> addRoutine(String name) async {
    final routine = SportRoutine(id: _newId(), name: name, items: const []);
    _routines.add(routine);
    notifyListeners();
    await _store.saveRoutines(_routines);
    return routine;
  }

  Future<void> removeRoutine(String id) async {
    _routines.removeWhere((routine) => routine.id == id);
    notifyListeners();
    await _store.saveRoutines(_routines);
  }

  Future<void> _replaceRoutine(SportRoutine routine) async {
    final index = _routines.indexWhere((other) => other.id == routine.id);
    if (index < 0) {
      return;
    }
    _routines[index] = routine;
    notifyListeners();
    await _store.saveRoutines(_routines);
  }

  Future<void> renameRoutine(String id, String name) async {
    final routine = routineById(id);
    if (routine != null) {
      await _replaceRoutine(routine.copyWith(name: name));
    }
  }

  Future<void> addRoutineItem(String routineId, String exerciseId) async {
    final routine = routineById(routineId);
    if (routine != null) {
      final item = RoutineItem(id: _newId(), exerciseId: exerciseId);
      await _replaceRoutine(routine.copyWith(items: [...routine.items, item]));
    }
  }

  Future<void> updateRoutineItem(
    String routineId,
    int index,
    RoutineItem item,
  ) async {
    final routine = routineById(routineId);
    if (routine == null || index < 0 || index >= routine.items.length) {
      return;
    }
    final items = [...routine.items]..[index] = item;
    await _replaceRoutine(routine.copyWith(items: items));
  }

  Future<void> removeRoutineItem(String routineId, int index) async {
    final routine = routineById(routineId);
    if (routine == null || index < 0 || index >= routine.items.length) {
      return;
    }
    final items = [...routine.items]..removeAt(index);
    await _replaceRoutine(routine.copyWith(items: items));
  }

  /// [newIndex] is already corrected for the removed entry
  /// (ReorderableListView.onReorderItem semantics).
  Future<void> reorderRoutineItems(
    String routineId,
    int oldIndex,
    int newIndex,
  ) async {
    final routine = routineById(routineId);
    if (routine == null) {
      return;
    }
    final items = [...routine.items];
    items.insert(newIndex, items.removeAt(oldIndex));
    await _replaceRoutine(routine.copyWith(items: items));
  }

  // ---- Sessions ----

  Future<void> addSession(WorkoutSession session) async {
    _sessions.add(session);
    notifyListeners();
    await _store.saveSessions(_sessions);
  }

  Future<void> removeSession(String id) async {
    _sessions.removeWhere((session) => session.id == id);
    notifyListeners();
    await _store.saveSessions(_sessions);
  }
}
