import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';

enum WorkoutPhase { exercising, resting, done }

/// Drives a running routine: current exercise + set, a wall-clock stopwatch
/// (survives backgrounding, computed from timestamps) and the rest countdown.
/// Logs one [SetLog] per set and delivers a [WorkoutSession] via [onFinished].
/// Persists a [WorkoutSnapshot] via [onPersist] on every state change so the
/// workout resumes after the app is closed. The rest does NOT auto-advance and
/// plays no tone: at 0 it counts up as overtime until the user continues or
/// extends it. UI-free.
class WorkoutRunner extends ChangeNotifier {
  final SportRoutine routine;
  final List<SportExercise> _exercises;
  final int _sessionStartedMs;

  /// Persist the current snapshot, or clear it (null) when the workout ends.
  final void Function(WorkoutSnapshot? snapshot)? onPersist;

  /// The same set of a previous session, for the "last time" comparison.
  final SetLog? Function(String exerciseId, int setIndex)? findLastSet;

  WorkoutPhase _phase;
  int _exerciseIndex;
  int _setIndex;
  int _currentReps;
  double _currentWeight;
  DateTime _setStartedAt;
  DateTime? _restEndsAt;
  Duration _pausedTotal;
  DateTime? _pausedAt;
  final List<SetLog> _sets = [];
  Timer? _ticker;

  /// Set by the UI: save the finished session + close the page.
  void Function(WorkoutSession session)? onFinished;

  WorkoutRunner(
    this.routine,
    List<SportExercise> exercises, {
    WorkoutSnapshot? resume,
    this.onPersist,
    this.findLastSet,
  }) : _exercises = exercises,
       _sessionStartedMs =
           resume?.startedAtMs ?? DateTime.now().millisecondsSinceEpoch,
       _phase = resume?.phase ?? WorkoutPhase.exercising,
       _exerciseIndex = resume?.exerciseIndex ?? 0,
       _setIndex = resume?.setIndex ?? 0,
       _currentReps = resume?.currentReps ?? routine.items.first.target,
       _currentWeight =
           resume?.currentWeight ?? routine.items.first.targetWeight,
       _setStartedAt = DateTime.fromMillisecondsSinceEpoch(
         resume?.setStartedAtMs ?? DateTime.now().millisecondsSinceEpoch,
       ),
       _restEndsAt = _dateOrNull(resume?.restEndsAtMs),
       _pausedTotal = Duration(milliseconds: resume?.pausedTotalMs ?? 0) {
    if (resume != null) {
      _sets.addAll(resume.sets);
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Persist right away so the workout shows up as resumable the moment it
    // starts — even before the first set or a pause.
    _persist();
  }

  static DateTime? _dateOrNull(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

  WorkoutPhase get phase => _phase;
  RoutineItem get currentItem => routine.items[_exerciseIndex];
  SportExercise? get currentExercise => _exerciseById(currentItem.exerciseId);
  int get exerciseIndex => _exerciseIndex;
  int get totalExercises => routine.items.length;
  int get setNumber => _setIndex + 1;
  int get totalSets => currentItem.targetSets;
  int get currentReps => _currentReps;
  double get currentWeight => _currentWeight;
  bool get isTimed => currentExercise?.kind == ExerciseKind.timed;
  bool get isWeighted => currentExercise?.kind == ExerciseKind.weighted;
  bool get isPaused => _pausedAt != null;

  /// The reference "now" — frozen at the pause moment while paused.
  DateTime get _now => _pausedAt ?? DateTime.now();

  /// Total workout time so far, excluding paused spans.
  Duration get sessionElapsed =>
      _now.difference(
        DateTime.fromMillisecondsSinceEpoch(_sessionStartedMs),
      ) -
      _pausedTotal;

  Duration get elapsed => _now.difference(_setStartedAt);

  Duration get restRemaining {
    final end = _restEndsAt;
    if (end == null) {
      return Duration.zero;
    }
    final left = end.difference(_now);
    return left.isNegative ? Duration.zero : left;
  }

  /// How far past 0 the rest has run (0 while still counting down).
  Duration get restOvertime {
    final end = _restEndsAt;
    if (end == null) {
      return Duration.zero;
    }
    final over = _now.difference(end);
    return over.isNegative ? Duration.zero : over;
  }

  bool get restExpired =>
      _phase == WorkoutPhase.resting && restRemaining == Duration.zero;

  /// Fraction of the routine's planned sets already completed (0..1).
  double get progress {
    final planned = _plannedSets;
    return planned == 0 ? 0 : (_sets.length / planned).clamp(0.0, 1.0);
  }

  int get _plannedSets {
    var total = 0;
    for (final item in routine.items) {
      total += item.targetSets;
    }
    return total;
  }

  /// The set just logged (editable during the following rest).
  SetLog? get lastLoggedSet => _sets.isEmpty ? null : _sets.last;

  /// The matching set from a previous session (competitive comparison).
  SetLog? get lastComparable =>
      findLastSet?.call(currentItem.exerciseId, _setIndex);

  SportExercise? _exerciseById(String id) {
    for (final exercise in _exercises) {
      if (exercise.id == id) {
        return exercise;
      }
    }
    return null;
  }

  void adjustReps(int delta) {
    _currentReps = (_currentReps + delta).clamp(0, 999);
    notifyListeners();
  }

  /// Set the reps actually achieved (from the inline field) before [completeSet]
  /// logs the set.
  void recordReps(int reps) {
    _currentReps = reps.clamp(0, 999);
  }

  void adjustWeight(double delta) {
    _currentWeight = (_currentWeight + delta).clamp(0, 999);
    notifyListeners();
  }

  /// Correct the just-logged set's reps/weight while resting.
  void updateLastSet({int? reps, double? weightKg}) {
    if (_sets.isEmpty) {
      return;
    }
    final last = _sets.last;
    _sets[_sets.length - 1] = SetLog(
      exerciseId: last.exerciseId,
      reps: reps ?? last.reps,
      seconds: last.seconds,
      weightKg: weightKg ?? last.weightKg,
      atEpochMs: last.atEpochMs,
    );
    notifyListeners();
    _persist();
  }

  void pause() {
    if (isPaused || _phase == WorkoutPhase.done) {
      return;
    }
    _pausedAt = DateTime.now();
    notifyListeners();
    _persist();
  }

  /// Resume: shift the set stopwatch and rest deadline forward by the paused
  /// span so both continue where they left off.
  void resume() {
    final since = _pausedAt;
    if (since == null) {
      return;
    }
    final delta = DateTime.now().difference(since);
    _pausedTotal += delta;
    _setStartedAt = _setStartedAt.add(delta);
    _restEndsAt = _restEndsAt?.add(delta);
    _pausedAt = null;
    notifyListeners();
    _persist();
  }

  /// Add [seconds] to the rest (from now if it already expired).
  void extendRest(int seconds) {
    if (_phase != WorkoutPhase.resting) {
      return;
    }
    final base = (_restEndsAt != null && _restEndsAt!.isAfter(_now))
        ? _restEndsAt!
        : _now;
    _restEndsAt = base.add(Duration(seconds: seconds));
    notifyListeners();
    _persist();
  }

  /// Log the current set and advance to the next set/exercise (with rest), or
  /// finish the session.
  void completeSet() {
    if (_phase != WorkoutPhase.exercising) {
      return;
    }
    _logCurrentSet();
    final rest = currentItem.restSeconds;
    if (!_advancePointers()) {
      _finish();
      return;
    }
    if (rest > 0) {
      _enterResting(rest);
    } else {
      _enterExercising();
    }
  }

  /// Continue from a finished rest.
  void skipRest() {
    if (_phase == WorkoutPhase.resting) {
      _enterExercising();
    }
  }

  /// Jump to any exercise (skip forward or back); starts its first set.
  void jumpTo(int exerciseIndex) {
    if (exerciseIndex < 0 || exerciseIndex >= routine.items.length) {
      return;
    }
    _exerciseIndex = exerciseIndex;
    _setIndex = 0;
    _enterExercising();
  }

  /// Finish the workout early (does NOT log the current set).
  void finishEarly() => _finish();

  void _logCurrentSet() {
    _sets.add(
      SetLog(
        exerciseId: currentItem.exerciseId,
        reps: isTimed ? null : _currentReps,
        seconds: isTimed ? elapsed.inSeconds : null,
        weightKg: isWeighted ? _currentWeight : null,
        atEpochMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Advances setIndex/exerciseIndex. false when nothing follows.
  bool _advancePointers() {
    if (_setIndex + 1 < currentItem.targetSets) {
      _setIndex += 1;
      return true;
    }
    if (_exerciseIndex + 1 < routine.items.length) {
      _exerciseIndex += 1;
      _setIndex = 0;
      return true;
    }
    return false;
  }

  void _enterResting(int seconds) {
    _phase = WorkoutPhase.resting;
    _restEndsAt = DateTime.now().add(Duration(seconds: seconds));
    notifyListeners();
    _persist();
  }

  void _enterExercising() {
    _phase = WorkoutPhase.exercising;
    _restEndsAt = null;
    _setStartedAt = DateTime.now();
    _currentReps = currentItem.target;
    _currentWeight = currentItem.targetWeight;
    notifyListeners();
    _persist();
  }

  /// Just repaints (overtime/stopwatch); never auto-advances the rest.
  void _tick() {
    if (isPaused) {
      return;
    }
    notifyListeners();
  }

  void _finish() {
    _phase = WorkoutPhase.done;
    _ticker?.cancel();
    onPersist?.call(null);
    onFinished?.call(
      WorkoutSession(
        id: _sessionStartedMs.toRadixString(36),
        routineId: routine.id,
        startedAtMs: _sessionStartedMs,
        sets: List.unmodifiable(_sets),
      ),
    );
    notifyListeners();
  }

  void _persist() {
    onPersist?.call(
      WorkoutSnapshot(
        routineId: routine.id,
        startedAtMs: _sessionStartedMs,
        exerciseIndex: _exerciseIndex,
        setIndex: _setIndex,
        phase: _phase,
        setStartedAtMs: _setStartedAt.millisecondsSinceEpoch,
        restEndsAtMs: _restEndsAt?.millisecondsSinceEpoch,
        pausedTotalMs: _pausedTotal.inMilliseconds,
        currentReps: _currentReps,
        currentWeight: _currentWeight,
        sets: List.of(_sets),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
