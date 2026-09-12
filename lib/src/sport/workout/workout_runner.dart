import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:insulink/src/sport/routines/routine_duration.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';

enum WorkoutPhase { exercising, resting, done }

/// Drives a running routine: current exercise + set, a wall-clock stopwatch
/// (survives backgrounding, computed from timestamps) and the rest countdown.
/// Logs one [SetLog] per set and delivers a [WorkoutSession] via [onFinished].
/// Persists a [WorkoutSnapshot] via [onPersist] on every state change so the
/// workout resumes after the app is closed. A fresh workout persists at once, so
/// it is resumable before the first set; a [resume]d one does NOT — that
/// snapshot is already stored, and pushing it back would republish a workout
/// this device is only following, recreating it when the device that owns it has
/// just finished it. The rest does NOT auto-advance and
/// plays no tone: at 0 it counts up as overtime until the user continues or
/// extends it. UI-free.
class WorkoutRunner extends ChangeNotifier {
  SportRoutine _routine;
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
  DateTime? _restStartedAt;
  Duration _pausedTotal;
  DateTime? _pausedAt;
  final List<SetLog> _sets = [];
  Timer? _ticker;

  /// Set by the UI: save the finished session + close the page.
  void Function(WorkoutSession session)? onFinished;

  WorkoutRunner(
    SportRoutine routine,
    List<SportExercise> exercises, {
    WorkoutSnapshot? resume,
    this.onPersist,
    this.findLastSet,
  }) : _routine = routine,
       _exercises = exercises,
       _sessionStartedMs =
           resume?.startedAtMs ?? DateTime.now().millisecondsSinceEpoch,
       _phase = resume?.phase ?? WorkoutPhase.exercising,
       _exerciseIndex = resume?.exerciseIndex ?? 0,
       _setIndex = resume?.setIndex ?? 0,
       _currentReps = resume?.currentReps ?? _firstTarget(routine),
       _currentWeight = resume?.currentWeight ?? _firstWeight(routine),
       _setStartedAt = DateTime.fromMillisecondsSinceEpoch(
         resume?.setStartedAtMs ?? DateTime.now().millisecondsSinceEpoch,
       ),
       _restEndsAt = _dateOrNull(resume?.restEndsAtMs),
       _restStartedAt = _dateOrNull(resume?.restStartedAtMs),
       _pausedTotal = Duration(milliseconds: resume?.pausedTotalMs ?? 0),
       _pausedAt = _dateOrNull(resume?.pausedAtMs) {
    if (resume != null) {
      _sets.addAll(resume.sets);
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    if (resume == null) {
      _persist();
    }
  }

  static DateTime? _dateOrNull(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

  /// A free workout starts with nothing to do, so there is no first item to take
  /// the opening targets from.
  static int _firstTarget(SportRoutine routine) =>
      routine.items.isEmpty ? 0 : routine.items.first.target;

  static double _firstWeight(SportRoutine routine) =>
      routine.items.isEmpty ? 0 : routine.items.first.targetWeight;

  /// The routine as THIS session runs it: the one it was started with plus
  /// whatever [addExercise] appended. The stored routine is never touched.
  SportRoutine get routine => _routine;

  /// False only for a free workout before its first exercise is picked — the
  /// exercise/rest views have nothing to show until then.
  bool get hasExercises => _routine.items.isNotEmpty;

  /// A free workout has no plan to run out of: it ends when the user says so,
  /// not when the last planned set is done.
  bool get _isFree => _routine.id == freeRoutineId;

  WorkoutPhase get phase => _phase;
  RoutineItem get currentItem => _routine.items[_exerciseIndex];
  SportExercise? get currentExercise => _exerciseById(currentItem.exerciseId);
  int get exerciseIndex => _exerciseIndex;
  int get totalExercises => _routine.items.length;
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
      _now.difference(DateTime.fromMillisecondsSinceEpoch(_sessionStartedMs)) -
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

  /// How much longer the workout is expected to run, or null when there is no
  /// plan to predict against (a free workout, or one already finished).
  ///
  /// Extrapolates THIS session's own pace — time elapsed per logged set — so it
  /// corrects itself as the workout goes and needs no model of rests, pauses or
  /// how long the user lingers. Before the first set there is nothing to measure
  /// and the routine's planned length stands in.
  ///
  /// ponytail: one average across all sets, not one per exercise — a routine
  /// mixing 30 s planks with 3 min squat sets predicts coarsely. Weight the
  /// remaining sets by their planned cost if that ever matters.
  Duration? get remaining {
    if (_isFree || _phase == WorkoutPhase.done) {
      return null;
    }
    final left = _plannedSets - _sets.length;
    if (left <= 0) {
      return Duration.zero;
    }
    if (_sets.isEmpty) {
      return Duration(seconds: plannedRoutineSeconds(_routine, _exercises));
    }
    return sessionElapsed * (left / _sets.length);
  }

  /// When the workout is expected to be over, or null while nothing can be
  /// predicted. Read from the wall clock, so a paused workout's end keeps moving
  /// out — which is exactly what a pause does to it.
  DateTime? get expectedEnd {
    final left = remaining;
    return left == null ? null : DateTime.now().add(left);
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
  SetLog? get lastComparable => hasExercises
      ? findLastSet?.call(currentItem.exerciseId, _setIndex)
      : null;

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
    _sets[_sets.length - 1] = _sets.last.copyWith(
      reps: reps,
      weightKg: weightKg,
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
    // Shift the rest start forward too, so the logged rest excludes paused spans
    // (same trick as [_setStartedAt] for the set stopwatch).
    _restStartedAt = _restStartedAt?.add(delta);
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

  /// Whether a free workout has done everything it was told to and is waiting to
  /// be told what comes next — the rest after its last set, where the UI asks for
  /// the next exercise instead of offering to carry on.
  ///
  /// Derived, not stored: a free workout plans one set per exercise, so having
  /// logged at least as many sets as it planned means the plan is spent. That
  /// keeps it true for a follower reading the snapshot as well, and an older
  /// free workout whose exercises still carry three sets simply runs them out
  /// first.
  bool get awaitingNextExercise =>
      _isFree && _phase == WorkoutPhase.resting && _sets.length >= _plannedSets;

  /// Add an exercise to THIS session — appended to the runner's own copy of the
  /// routine, so the stored routine keeps its items and the snapshot carries the
  /// added one to every other screen. It starts straight away when the workout
  /// has nothing else to do (a free workout before its first pick, or resting
  /// after its last set); inside a running routine it queues up behind what is
  /// left.
  ///
  /// A free workout takes ONE set and a two-minute rest: it is picked exercise by
  /// exercise as it goes, so planning three sets ahead would only be in the way.
  /// An extra exercise in a real routine keeps the routine editor's defaults —
  /// there it IS part of a plan.
  void addExercise(String exerciseId) {
    final startNow = _routine.items.isEmpty || awaitingNextExercise;
    final item = RoutineItem(
      id: 'adhoc-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      exerciseId: exerciseId,
      targetSets: _isFree ? 1 : 3,
      restSeconds: _isFree ? 120 : 60,
    );
    _routine = _routine.copyWith(items: [..._routine.items, item]);
    if (startNow) {
      _exerciseIndex = _routine.items.length - 1;
      _setIndex = 0;
      _enterExercising();
      return;
    }
    notifyListeners();
    _persist();
  }

  /// Log the current set and advance to the next set/exercise (with rest), or
  /// finish the session. A free workout is never finished by running out of
  /// plan: it rests on the same set instead, so the user can add the next
  /// exercise, repeat this one, or end it themselves.
  void completeSet() {
    if (_phase != WorkoutPhase.exercising) {
      return;
    }
    _logCurrentSet();
    final rest = currentItem.restSeconds;
    if (!_advancePointers() && !_isFree) {
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
        durationSecs: elapsed.inSeconds,
        atEpochMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// On leaving a rest, stamp the rest actually taken onto the set it followed
  /// (the last logged set). No-op when no rest was active (e.g. a zero-rest
  /// advance or a jump straight from exercising).
  void _recordRestForLastSet() {
    final startedAt = _restStartedAt;
    if (startedAt == null || _sets.isEmpty) {
      return;
    }
    final rest = DateTime.now().difference(startedAt);
    _sets[_sets.length - 1] = _sets.last.copyWith(restSecs: rest.inSeconds);
    _restStartedAt = null;
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
    _restStartedAt = DateTime.now();
    _restEndsAt = _restStartedAt!.add(Duration(seconds: seconds));
    notifyListeners();
    _persist();
  }

  void _enterExercising() {
    _recordRestForLastSet();
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
        routineName: routine.name,
        items: routine.items,
        startedAtMs: _sessionStartedMs,
        exerciseIndex: _exerciseIndex,
        setIndex: _setIndex,
        phase: _phase,
        setStartedAtMs: _setStartedAt.millisecondsSinceEpoch,
        restEndsAtMs: _restEndsAt?.millisecondsSinceEpoch,
        restStartedAtMs: _restStartedAt?.millisecondsSinceEpoch,
        pausedTotalMs: _pausedTotal.inMilliseconds,
        pausedAtMs: _pausedAt?.millisecondsSinceEpoch,
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
