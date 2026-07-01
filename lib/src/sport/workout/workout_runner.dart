import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:insulink/src/sport/sport_models.dart';

enum WorkoutPhase { exercising, resting, done }

/// Drives a running routine: current exercise + set, a wall-clock-based
/// stopwatch (survives backgrounding, since computed from timestamps) and the
/// rest countdown. Logs one [SetLog] per set and delivers a [WorkoutSession] at
/// the end via [onFinished]. UI-/audio-free — the page attaches [onRestFinished]
/// (tone) and [onFinished] (save).
class WorkoutRunner extends ChangeNotifier {
  final SportRoutine routine;
  final List<SportExercise> _exercises;
  final int _sessionStartedMs;

  WorkoutPhase _phase = WorkoutPhase.exercising;
  int _exerciseIndex = 0;
  int _setIndex = 0;
  int _currentReps;
  double _currentWeight;
  DateTime _setStartedAt;
  DateTime? _restEndsAt;
  bool _restAlerted = false;
  final List<SetLog> _sets = [];
  Timer? _ticker;

  /// Set by the UI: tone when the rest expires.
  VoidCallback? onRestFinished;

  /// Set by the UI: save the finished session + close the page.
  void Function(WorkoutSession session)? onFinished;

  WorkoutRunner(this.routine, List<SportExercise> exercises)
    : _exercises = exercises,
      _sessionStartedMs = DateTime.now().millisecondsSinceEpoch,
      _currentReps = routine.items.first.target,
      _currentWeight = routine.items.first.targetWeight,
      _setStartedAt = DateTime.now() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

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

  Duration get elapsed => DateTime.now().difference(_setStartedAt);

  Duration get restRemaining {
    final end = _restEndsAt;
    if (end == null) {
      return Duration.zero;
    }
    final left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

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

  /// Skip the remaining rest.
  void skipRest() {
    if (_phase == WorkoutPhase.resting) {
      _enterExercising();
    }
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
    _restAlerted = false;
    notifyListeners();
  }

  void _enterExercising() {
    _phase = WorkoutPhase.exercising;
    _restEndsAt = null;
    _setStartedAt = DateTime.now();
    _currentReps = currentItem.target;
    _currentWeight = currentItem.targetWeight;
    notifyListeners();
  }

  void _tick() {
    if (_phase == WorkoutPhase.resting &&
        _restEndsAt != null &&
        !DateTime.now().isBefore(_restEndsAt!)) {
      if (!_restAlerted) {
        _restAlerted = true;
        onRestFinished?.call();
      }
      _enterExercising();
      return;
    }
    notifyListeners();
  }

  void _finish() {
    _phase = WorkoutPhase.done;
    _ticker?.cancel();
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

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
