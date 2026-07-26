import 'dart:async';
import 'dart:convert';

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
  /// How often the account is asked whether the workout changed elsewhere. Fast
  /// enough that picking the phone up after starting a routine in the panel
  /// shows it straight away, slow enough to cost nothing.
  static const _watchEvery = Duration(seconds: 5);

  /// The same question while a runner is actually open. Someone is working out
  /// on one of the two screens right now and watching the other; a set arriving
  /// five seconds late reads as "it doesn't sync at all". A snapshot is small and
  /// the phone is awake anyway (the runner holds the wakelock).
  static const _watchEveryWithRunner = Duration(seconds: 2);

  final SportStore _store;
  final List<SportExercise> _exercises;
  final List<SportRoutine> _routines;
  final List<WorkoutSession> _sessions;
  WorkoutSnapshot? _activeWorkout;
  Timer? _watchTimer;
  bool _driving = false;
  bool _endedElsewhere = false;

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

  /// Re-read the library, routines and logbook into THIS instance, so a pull that
  /// replaced them reaches the UI. The provider keeps this instance, so listeners
  /// just rebuild.
  ///
  /// [activeWorkout] is deliberately NOT reloaded: it has its own account watcher
  /// ([watchActiveWorkout]) that owns it, and every listener notification here is
  /// read by the app shell as "a workout appeared" — which opens its runner. A
  /// refresh must never do that behind the user's back.
  Future<void> reload() async {
    final fresh = await TrainingState.load();
    _exercises
      ..clear()
      ..addAll(fresh._exercises);
    _routines
      ..clear()
      ..addAll(fresh._routines);
    _sessions
      ..clear()
      ..addAll(fresh._sessions);
    notifyListeners();
  }

  List<SportExercise> get exercises => List.unmodifiable(_exercises);
  List<SportRoutine> get routines => List.unmodifiable(_routines);
  List<WorkoutSession> get sessions => List.unmodifiable(_sessions);

  /// The in-progress workout to auto-resume on launch (null when none).
  WorkoutSnapshot? get activeWorkout => _activeWorkout;

  /// Persist the running workout's snapshot (called by the runner on every
  /// state change). Notifies AFTER the write (a later microtask, so it never
  /// fires inside the runner page's own build frame) so the "resume" banner in
  /// the activities list appears/updates the moment a workout starts or ends —
  /// the runner still owns its own live UI. Also mirrors the snapshot to the
  /// account, so the web panel can follow or take the workout over.
  Future<void> saveActiveWorkout(WorkoutSnapshot snapshot) async {
    _activeWorkout = snapshot;
    await _store.saveActiveWorkout(snapshot);
    SportSync().pushActiveWorkout(snapshot);
    notifyListeners();
  }

  Future<void> clearActiveWorkout() async {
    _activeWorkout = null;
    _endedElsewhere = false;
    await _store.clearActiveWorkout();
    unawaited(SportSync().clearActiveWorkout());
    notifyListeners();
  }

  // ---- following the account's workout across devices ----

  /// Whether the workout this device had open was ended somewhere else (the web
  /// panel, another phone). The runner page reads this to say so and close;
  /// [acknowledgeEndedElsewhere] clears it once it has.
  bool get endedElsewhere => _endedElsewhere;

  /// Whether this device currently drives the workout (its runner is open).
  bool get drivingActiveWorkout => _driving;

  /// Marks this device as the one showing the workout — set while the runner
  /// page is open. It only keeps a second runner from being opened on top and
  /// tells an end elsewhere apart from a workout that was never on the account;
  /// it does NOT stop the account's copy from being adopted. The runner having
  /// the page open does not make this device the one moving the workout on: the
  /// panel may be doing that, and ignoring its snapshots is what left the phone
  /// ticking away on a set the user finished ages ago.
  void driveActiveWorkout(bool driving) {
    if (_driving == driving) {
      return;
    }
    _driving = driving;
    if (_watchTimer != null) {
      watchActiveWorkout();
    }
  }

  /// Follows the account's running workout, so a routine started or ended in the
  /// web panel reaches this device without a restart. Idempotent; pulls once
  /// immediately so returning to the app shows the truth at once rather than
  /// after the first tick.
  void watchActiveWorkout() {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(
      _driving ? _watchEveryWithRunner : _watchEvery,
      (_) => _followActiveWorkout(),
    );
    unawaited(_followActiveWorkout());
  }

  void stopWatchingActiveWorkout() {
    _watchTimer?.cancel();
    _watchTimer = null;
  }

  /// One poll of the account. An unreachable account changes nothing — reading a
  /// failed request as "no workout runs" ends the workout on this device over a
  /// moment of no signal.
  Future<void> _followActiveWorkout() async {
    final confirmedStart = SportSync.confirmedActiveWorkoutStart;
    final answer = await SportSync().pullActiveWorkout(null);
    if (answer == null) {
      return;
    }
    final remote = answer.snapshot;
    if (remote == null) {
      await _adoptEndedWorkout(confirmedStart);
      return;
    }
    if (!answer.foreign || _matchesActive(remote)) {
      return;
    }
    _activeWorkout = remote;
    await _store.saveActiveWorkout(remote);
    notifyListeners();
  }

  /// The account has no workout. That only ends the session here when the account
  /// had confirmed THIS workout beforehand ([confirmedStart] is its start) — a
  /// push it accepted, or a poll that answered with it.
  ///
  /// Otherwise the account has simply never heard of it: a workout just started
  /// on this device goes up only after a short debounce, and a poll firing inside
  /// that window would wipe it from the shared state the moment it began. The
  /// runner then ticks on over a session nothing else knows about, and nothing
  /// syncs for the rest of the workout.
  Future<void> _adoptEndedWorkout(int confirmedStart) async {
    final local = _activeWorkout;
    if (local == null || confirmedStart != local.startedAtMs) {
      return;
    }
    _activeWorkout = null;
    _endedElsewhere = _driving;
    await _store.clearActiveWorkout();
    notifyListeners();
  }

  void acknowledgeEndedElsewhere() {
    _endedElsewhere = false;
  }

  /// Compared by their JSON so an unchanged poll does not rebuild the tree every
  /// few seconds — and so another device echoing this device's own snapshot back
  /// (the panel mirrors what it adopts) does not restart the runner over state it
  /// already holds. [WorkoutSnapshot] is a plain value object without `==`, and
  /// giving it one only for this would be the longer way round.
  bool _matchesActive(WorkoutSnapshot remote) {
    final local = _activeWorkout;
    if (local == null) {
      return false;
    }
    return jsonEncode(local.toJson()) == jsonEncode(remote.toJson());
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    super.dispose();
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

  /// The routine to run a followed/resumed [snapshot] against. Prefers the
  /// routine the DRIVER embedded in the snapshot, so the exercise/set/target
  /// shown matches what that device is on even when this device's own copy of
  /// the routine differs or is missing entirely (a workout started in the web
  /// panel). Falls back to the local routine for a legacy snapshot without
  /// embedded items.
  SportRoutine? routineForSnapshot(WorkoutSnapshot snapshot) {
    if (snapshot.items.isNotEmpty) {
      return SportRoutine(
        id: snapshot.routineId,
        name: snapshot.routineName,
        items: snapshot.items,
      );
    }
    return routineById(snapshot.routineId);
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

  /// Reorders the routine list. [newIndex] is already corrected for the removed
  /// entry (ReorderableListView.onReorderItem semantics).
  Future<void> reorderRoutines(int oldIndex, int newIndex) async {
    _routines.insert(newIndex, _routines.removeAt(oldIndex));
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

  /// The session of the same routine logged right before [session] — the one to
  /// compare an end-of-workout summary against. Null when it is the first of its
  /// routine. Not keyed on order in the list: compares by start time so an edited
  /// or re-synced logbook still finds the true predecessor.
  WorkoutSession? previousSessionOf(WorkoutSession session) {
    WorkoutSession? previous;
    for (final other in _sessions) {
      if (other.routineId != session.routineId ||
          other.startedAtMs >= session.startedAtMs) {
        continue;
      }
      if (previous == null || other.startedAtMs > previous.startedAtMs) {
        previous = other;
      }
    }
    return previous;
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
