import 'package:flutter/foundation.dart';

import 'sport_models.dart';
import 'sport_store.dart';
import 'sport_sync.dart';
import 'workout/workout_snapshot.dart';

/// Shared training state: exercise library, routines and logged sessions. Its
/// own [ChangeNotifier] alongside [SportState] (weight) so both files stay
/// focused. Pattern: static [load], mutators mutate → [notifyListeners] →
/// persist.
class TrainingState extends ChangeNotifier {
  final SportStore _store;
  final List<SportExercise> _exercises;
  final List<SportRoutine> _routines;
  final List<WorkoutSession> _sessions;
  WorkoutSnapshot? _activeWorkout;

  TrainingState(
    this._store,
    this._exercises,
    this._routines,
    this._sessions,
    this._activeWorkout,
  );

  static Future<TrainingState> load() async {
    const store = SportStore();
    return TrainingState(
      store,
      await store.loadExercises(),
      await store.loadRoutines(),
      await store.loadSessions(),
      await store.loadActiveWorkout(),
    );
  }

  List<SportExercise> get exercises => List.unmodifiable(_exercises);
  List<SportRoutine> get routines => List.unmodifiable(_routines);
  List<WorkoutSession> get sessions => List.unmodifiable(_sessions);

  /// The in-progress workout to auto-resume on launch (null when none).
  WorkoutSnapshot? get activeWorkout => _activeWorkout;

  /// Persist the running workout's snapshot (called by the runner on every
  /// state change). No [notifyListeners] — the runner owns the live UI.
  Future<void> saveActiveWorkout(WorkoutSnapshot snapshot) async {
    _activeWorkout = snapshot;
    await _store.saveActiveWorkout(snapshot);
  }

  Future<void> clearActiveWorkout() async {
    _activeWorkout = null;
    await _store.clearActiveWorkout();
  }

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

  int _idCounter = 0;

  /// Unique id — the counter guards against collisions when several ids are
  /// generated within the same microsecond (e.g. duplicating a routine's items).
  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_idCounter++}';

  // ---- Exercises ----

  Future<SportExercise> addExercise(String name, ExerciseKind kind) async {
    final exercise = SportExercise(id: _newId(), name: name, kind: kind);
    _exercises.add(exercise);
    notifyListeners();
    await _saveExercises();
    return exercise;
  }

  Future<void> updateExercise(SportExercise exercise) async {
    final index = _exercises.indexWhere((other) => other.id == exercise.id);
    if (index < 0) {
      return;
    }
    _exercises[index] = exercise;
    notifyListeners();
    await _saveExercises();
  }

  Future<void> removeExercise(String id) async {
    _exercises.removeWhere((exercise) => exercise.id == id);
    notifyListeners();
    await _saveExercises();
  }

  /// Reorders the exercise library. [newIndex] is already corrected for the
  /// removed entry (ReorderableListView.onReorderItem semantics).
  Future<void> reorderExercises(int oldIndex, int newIndex) async {
    _exercises.insert(newIndex, _exercises.removeAt(oldIndex));
    notifyListeners();
    await _saveExercises();
  }

  /// Copies an exercise (fresh id, name + [copySuffix]).
  Future<void> duplicateExercise(String id, String copySuffix) async {
    final source = exerciseById(id);
    if (source == null) {
      return;
    }
    _exercises.add(
      SportExercise(
        id: _newId(),
        name: '${source.name}$copySuffix',
        kind: source.kind,
      ),
    );
    notifyListeners();
    await _saveExercises();
  }

  // ---- Routines ----

  Future<SportRoutine> addRoutine(String name) async {
    final routine = SportRoutine(id: _newId(), name: name, items: const []);
    _routines.add(routine);
    notifyListeners();
    await _saveRoutines();
    return routine;
  }

  Future<void> removeRoutine(String id) async {
    _routines.removeWhere((routine) => routine.id == id);
    notifyListeners();
    await _saveRoutines();
  }

  /// Copies a routine (fresh routine id, fresh item ids, name + [copySuffix]).
  Future<void> duplicateRoutine(String id, String copySuffix) async {
    final source = routineById(id);
    if (source == null) {
      return;
    }
    _routines.add(
      SportRoutine(
        id: _newId(),
        name: '${source.name}$copySuffix',
        items: [
          for (final item in source.items)
            RoutineItem(
              id: _newId(),
              exerciseId: item.exerciseId,
              targetSets: item.targetSets,
              target: item.target,
              targetWeight: item.targetWeight,
              restSeconds: item.restSeconds,
            ),
        ],
      ),
    );
    notifyListeners();
    await _saveRoutines();
  }

  Future<void> _replaceRoutine(SportRoutine routine) async {
    final index = _routines.indexWhere((other) => other.id == routine.id);
    if (index < 0) {
      return;
    }
    _routines[index] = routine;
    notifyListeners();
    await _saveRoutines();
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
    await _saveSessions();
  }

  Future<void> removeSession(String id) async {
    _sessions.removeWhere((session) => session.id == id);
    notifyListeners();
    await _saveSessions();
  }

  /// Replace a logged session in place (edited sets in the logbook). No-op if
  /// the id is gone.
  Future<void> updateSession(WorkoutSession session) async {
    final index = _sessions.indexWhere((other) => other.id == session.id);
    if (index < 0) {
      return;
    }
    _sessions[index] = session;
    notifyListeners();
    await _saveSessions();
  }

  /// The most recent logged set for [exerciseId] at [setIndex] (0-based) across
  /// past sessions — powers the "last time" comparison in the runner. Sessions
  /// are appended in order, so iterating in reverse yields newest first.
  SetLog? lastSetFor(String exerciseId, int setIndex) {
    for (final session in _sessions.reversed) {
      final matching = [
        for (final set in session.sets)
          if (set.exerciseId == exerciseId) set,
      ];
      if (setIndex < matching.length) {
        return matching[setIndex];
      }
    }
    return null;
  }

  // ---- Persistence (each save also queues a backend sync) ----

  Future<void> _saveExercises() async {
    await _store.saveExercises(_exercises);
    SportSync().pushExercises();
  }

  Future<void> _saveRoutines() async {
    await _store.saveRoutines(_routines);
    SportSync().pushRoutines();
  }

  Future<void> _saveSessions() async {
    await _store.saveSessions(_sessions);
    SportSync().pushWorkouts();
  }
}
