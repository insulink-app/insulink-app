import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';

/// Changing the plan mid-workout. A swap or a skip belongs to the SESSION: the
/// stored routine must come out unchanged, and the snapshot must carry the new
/// items so a following device shows the same exercise. The "last time"
/// comparison is scoped to the routine and already names the next set while
/// resting.
void main() {
  const bench = RoutineItem(
    id: 'i1',
    exerciseId: 'bench',
    targetSets: 2,
    target: 8,
    targetWeight: 40,
    restSeconds: 90,
  );
  const plank = RoutineItem(id: 'i2', exerciseId: 'plank', targetSets: 1);
  const routine = SportRoutine(id: 'r1', name: 'Push', items: [bench, plank]);

  test('a swap replaces the exercise in the session only', () {
    final persisted = <WorkoutSnapshot?>[];
    final runner = WorkoutRunner(routine, const [], onPersist: persisted.add);

    runner.swapExercise('dips');

    expect(routine.items, [bench, plank]);
    final swapped = runner.routine.items.first;
    expect(swapped.exerciseId, 'dips');
    expect(swapped.id, isNot(bench.id));
    expect(swapped.targetSets, 2);
    expect(swapped.target, 8);
    expect(runner.currentReps, 8);
    expect(persisted.last!.items.first.exerciseId, 'dips');
    runner.dispose();
  });

  test(
    'a swap while resting swaps the exercise coming up, from its first set',
    () {
      final runner = WorkoutRunner(routine, const []);
      runner.completeSet();

      runner.swapExercise('dips');

      expect(runner.phase, WorkoutPhase.resting);
      expect(runner.setNumber, 1);
      expect(runner.currentItem.exerciseId, 'dips');
      runner.dispose();
    },
  );

  test('a skip leaves the remaining sets unlogged and starts the next', () {
    final runner = WorkoutRunner(routine, const []);
    runner.completeSet();

    runner.skipExercise();

    expect(runner.phase, WorkoutPhase.exercising);
    expect(runner.currentItem.exerciseId, 'plank');
    expect(runner.canSkipExercise, isFalse);
    runner.finishEarly();
    runner.dispose();
  });

  test('the last exercise cannot be skipped', () {
    final runner = WorkoutRunner(routine, const []);
    runner.jumpTo(1);

    runner.skipExercise();

    expect(runner.currentItem.exerciseId, 'plank');
    runner.dispose();
  });

  test('the comparison asks for this routine and, resting, the next set', () {
    final asked = <String>[];
    final runner = WorkoutRunner(
      routine,
      const [],
      findLastSet: (routineId, exerciseId, setIndex) {
        asked.add('$routineId/$exerciseId/$setIndex');
        return null;
      },
    );

    runner.lastComparable;
    runner.completeSet();
    runner.lastComparable;

    expect(asked, ['r1/bench/0', 'r1/bench/1']);
    runner.dispose();
  });

  test('jumping back to a logged exercise prefills what was done there', () {
    final runner = WorkoutRunner(routine, const [
      SportExercise(id: 'bench', name: 'Bench', kind: ExerciseKind.weighted),
    ]);
    runner.recordReps(6);
    runner.adjustWeight(2.5);
    runner.completeSet();
    runner.skipExercise();
    expect(runner.currentReps, plank.target);

    runner.jumpTo(0);

    expect(runner.currentReps, 6);
    expect(runner.currentWeight, 42.5);
    runner.dispose();
  });
}
