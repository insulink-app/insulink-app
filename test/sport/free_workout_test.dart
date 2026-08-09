import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';

/// Exercises picked while the workout runs. Two rules carry the feature: an
/// added exercise belongs to the SESSION (the stored routine must come out
/// unchanged, or a spontaneous extra rewrites the plan for every future run),
/// and a free workout must not end itself when the last picked exercise is done
/// — there would be no way to add the next one.
void main() {
  const item = RoutineItem(id: 'i1', exerciseId: 'bench', targetSets: 1);
  const routine = SportRoutine(id: 'r1', name: 'Push', items: [item]);
  const free = SportRoutine(id: freeRoutineId, name: 'Free', items: []);
  const exercise = SportExercise(
    id: 'bench',
    name: 'Bench',
    kind: ExerciseKind.reps,
  );
  const squat = SportExercise(
    id: 'squat',
    name: 'Squat',
    kind: ExerciseKind.reps,
  );

  test('an added exercise runs in the session only', () {
    final persisted = <WorkoutSnapshot?>[];
    final runner = WorkoutRunner(routine, const [], onPersist: persisted.add);

    runner.addExercise('squat');

    expect(routine.items, [item]);
    expect(runner.routine.items.map((entry) => entry.exerciseId), [
      'bench',
      'squat',
    ]);
    expect(persisted.last!.items.length, 2);
    runner.dispose();
  });

  test('a routine still finishes when its last planned set is done', () {
    var finished = false;
    final runner = WorkoutRunner(routine, const [])
      ..onFinished = (_) => finished = true;

    runner.completeSet();

    expect(finished, isTrue);
    expect(runner.phase, WorkoutPhase.done);
    runner.dispose();
  });

  test('a free workout rests instead of finishing, and keeps its sets', () {
    var finished = false;
    final runner = WorkoutRunner(free, const [])
      ..onFinished = (_) => finished = true;

    runner.addExercise('bench');
    runner.completeSet();
    runner.completeSet();
    runner.completeSet();

    expect(runner.hasExercises, isTrue);
    expect(finished, isFalse);
    expect(runner.phase, WorkoutPhase.resting);
    runner.dispose();
  });

  /// A free workout is picked exercise by exercise: one set, a two-minute rest,
  /// then the question what comes next. Three sets planned ahead would have the
  /// user repeating an exercise they only meant to do once.
  test('a picked exercise is one set and a two-minute rest', () {
    final runner = WorkoutRunner(free, const [exercise]);

    runner.addExercise('bench');

    expect(runner.routine.items.single.targetSets, 1);
    expect(runner.routine.items.single.restSeconds, 120);
    runner.dispose();
  });

  test('the set done, the free workout rests and asks what comes next', () {
    final runner = WorkoutRunner(free, const [exercise]);
    runner.addExercise('bench');

    runner.completeSet();

    expect(runner.phase, WorkoutPhase.resting);
    expect(runner.awaitingNextExercise, isTrue);
    expect(runner.restRemaining.inSeconds, greaterThan(110));
    runner.dispose();
  });

  test('the exercise picked during that rest starts straight away', () {
    final runner = WorkoutRunner(free, const [exercise, squat]);
    runner.addExercise('bench');
    runner.completeSet();

    runner.addExercise('squat');

    expect(runner.phase, WorkoutPhase.exercising);
    expect(runner.awaitingNextExercise, isFalse);
    expect(runner.currentExercise!.id, 'squat');
    expect(runner.setNumber, 1);
    runner.dispose();
  });

  test('an exercise added to a ROUTINE waits its turn and keeps the plan', () {
    final runner = WorkoutRunner(routine, const [exercise, squat]);

    runner.addExercise('squat');

    expect(runner.routine.items.last.targetSets, 3);
    expect(runner.currentItem.exerciseId, 'bench');
    runner.dispose();
  });

  test('the first exercise of a free workout starts it', () {
    final runner = WorkoutRunner(free, const []);

    expect(runner.hasExercises, isFalse);
    runner.addExercise('bench');

    expect(runner.hasExercises, isTrue);
    expect(runner.phase, WorkoutPhase.exercising);
    expect(runner.exerciseIndex, 0);
    expect(runner.setNumber, 1);
    runner.dispose();
  });
}
