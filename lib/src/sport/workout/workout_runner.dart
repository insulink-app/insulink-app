import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:insulink/src/sport/sport_models.dart';

enum WorkoutPhase { exercising, resting, done }

/// Steuert eine laufende Routine: aktuelle Übung + Satz, eine wall-clock-basierte
/// Stoppuhr (überlebt Hintergrund, da aus Zeitstempeln berechnet) und der
/// Pausen-Countdown. Protokolliert je Satz einen [SetLog] und liefert am Ende
/// eine [WorkoutSession] über [onFinished]. UI-/Audio-frei — die Page hängt
/// [onRestFinished] (Ton) und [onFinished] (Speichern) ein.
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

  /// Vom UI gesetzt: Ton, wenn die Pause abläuft.
  VoidCallback? onRestFinished;

  /// Vom UI gesetzt: fertige Session speichern + Seite schließen.
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

  void adjustWeight(double delta) {
    _currentWeight = (_currentWeight + delta).clamp(0, 999);
    notifyListeners();
  }

  /// Aktuellen Satz protokollieren und zum nächsten Satz/Übung wechseln (mit
  /// Pause), oder die Session abschließen.
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

  /// Verbleibende Pause überspringen.
  void skipRest() {
    if (_phase == WorkoutPhase.resting) {
      _enterExercising();
    }
  }

  /// Training vorzeitig beenden (protokolliert den laufenden Satz NICHT).
  void finishEarly() => _finish();

  void _logCurrentSet() {
    _sets.add(SetLog(
      exerciseId: currentItem.exerciseId,
      reps: isTimed ? null : _currentReps,
      seconds: isTimed ? elapsed.inSeconds : null,
      weightKg: isWeighted ? _currentWeight : null,
      atEpochMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// Rückt setIndex/exerciseIndex vor. false, wenn nichts mehr folgt.
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
    onFinished?.call(WorkoutSession(
      id: _sessionStartedMs.toRadixString(36),
      routineId: routine.id,
      startedAtMs: _sessionStartedMs,
      sets: List.unmodifiable(_sets),
    ));
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
