import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';

/// Who publishes the running workout. A runner that RESUMES one is following a
/// workout another device owns — the panel, or this phone before a restart — so
/// it must not push that snapshot back out. Doing so recreates the workout on
/// every device when the owner has just finished it, and the zombie is then
/// logged a second time under the same id. A workout STARTED here has to be
/// published at once, or nothing offers it for resume until the first set.
void main() {
  const item = RoutineItem(id: 'i1', exerciseId: 'bench', targetSets: 3);
  const routine = SportRoutine(id: 'r1', name: 'Push', items: [item]);
  const resume = WorkoutSnapshot(
    routineId: 'r1',
    routineName: 'Push',
    items: [item],
    startedAtMs: 1000,
    exerciseIndex: 0,
    setIndex: 1,
    phase: WorkoutPhase.exercising,
    setStartedAtMs: 1000,
    restEndsAtMs: null,
    restStartedAtMs: null,
    pausedTotalMs: 0,
    currentReps: 10,
    currentWeight: 40,
    sets: [],
  );

  test('a fresh workout is published straight away', () {
    final persisted = <WorkoutSnapshot?>[];

    WorkoutRunner(routine, const [], onPersist: persisted.add).dispose();

    expect(persisted.single!.startedAtMs, isNonZero);
  });

  test('a resumed workout is not published back', () {
    final persisted = <WorkoutSnapshot?>[];

    WorkoutRunner(
      routine,
      const [],
      resume: resume,
      onPersist: persisted.add,
    ).dispose();

    expect(persisted, isEmpty);
  });

  /// The pause travels with the snapshot, or the two screens disagree about
  /// whether the clock is running: the follower counts on while the driver sits
  /// paused, and adopting a snapshot silently un-pauses the workout.
  test('a workout paused elsewhere resumes paused', () {
    const paused = WorkoutSnapshot(
      routineId: 'r1',
      items: [item],
      startedAtMs: 1000,
      exerciseIndex: 0,
      setIndex: 0,
      phase: WorkoutPhase.exercising,
      setStartedAtMs: 1000,
      restEndsAtMs: null,
      restStartedAtMs: null,
      pausedTotalMs: 0,
      pausedAtMs: 5000,
      currentReps: 10,
      currentWeight: 40,
      sets: [],
    );

    final runner = WorkoutRunner(routine, const [], resume: paused);

    expect(runner.isPaused, isTrue);
    runner.dispose();
  });

  test('a pause is published so the other screen can freeze too', () {
    final persisted = <WorkoutSnapshot?>[];

    WorkoutRunner(routine, const [], onPersist: persisted.add)
      ..pause()
      ..dispose();

    expect(persisted.last!.pausedAtMs, isNotNull);
    expect(WorkoutSnapshot.fromJson(persisted.last!.toJson()).pausedAtMs,
        persisted.last!.pausedAtMs);
  });

  test('acting on a resumed workout publishes it again', () {
    final persisted = <WorkoutSnapshot?>[];

    WorkoutRunner(routine, const [], resume: resume, onPersist: persisted.add)
      ..pause()
      ..dispose();

    expect(persisted.single!.setIndex, 1);
  });
}
