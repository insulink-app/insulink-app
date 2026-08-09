import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';

/// The predicted end of a running routine. It extrapolates the session's own
/// pace, so the only things that can go wrong quietly are the edges: no set
/// logged yet (nothing measured — the plan stands in), nothing left to do, and a
/// free workout, which has no plan to predict against at all.
void main() {
  const item = RoutineItem(
    id: 'i1',
    exerciseId: 'bench',
    targetSets: 4,
    restSeconds: 30,
  );
  const routine = SportRoutine(id: 'r1', name: 'Push', items: [item]);
  const exercise = SportExercise(
    id: 'bench',
    name: 'Bench',
    kind: ExerciseKind.reps,
  );

  /// A runner resumed two sets in, started [elapsedSecs] ago.
  WorkoutRunner running(int elapsedSecs) {
    final startedAt =
        DateTime.now().millisecondsSinceEpoch - elapsedSecs * 1000;
    return WorkoutRunner(
      routine,
      const [exercise],
      resume: WorkoutSnapshot(
        routineId: 'r1',
        items: const [item],
        startedAtMs: startedAt,
        exerciseIndex: 0,
        setIndex: 2,
        phase: WorkoutPhase.exercising,
        setStartedAtMs: startedAt,
        restEndsAtMs: null,
        restStartedAtMs: null,
        pausedTotalMs: 0,
        currentReps: 10,
        currentWeight: 40,
        sets: [
          SetLog(exerciseId: 'bench', reps: 10, atEpochMs: startedAt),
          SetLog(exerciseId: 'bench', reps: 10, atEpochMs: startedAt),
        ],
      ),
    );
  }

  test('the remaining time follows the pace of the sets already logged', () {
    final runner = running(180);

    expect(runner.remaining!.inSeconds, closeTo(180, 2));
    expect(
      runner.expectedEnd!.difference(DateTime.now()).inSeconds,
      closeTo(180, 2),
    );
    runner.dispose();
  });

  test('before the first set the routine plan stands in', () {
    final runner = WorkoutRunner(routine, const [exercise]);

    expect(runner.remaining!.inSeconds, 4 * (60 + 30));
    runner.dispose();
  });

  test('a free workout predicts nothing', () {
    const free = SportRoutine(id: freeRoutineId, name: 'Free', items: []);
    final runner = WorkoutRunner(free, const [exercise]);

    expect(runner.remaining, isNull);
    expect(runner.expectedEnd, isNull);
    runner.dispose();
  });

  test('a finished workout predicts nothing', () {
    final runner = running(180)..finishEarly();

    expect(runner.remaining, isNull);
    runner.dispose();
  });
}
