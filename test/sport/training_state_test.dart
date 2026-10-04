import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  WorkoutSnapshot snapshot(String routineId, {List<RoutineItem> items = const []}) =>
      WorkoutSnapshot(
        routineId: routineId,
        routineName: 'Push',
        items: items,
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
        sets: const [],
      );

  SetLog setLog(String exerciseId, {int reps = 10, int at = 0}) =>
      SetLog(exerciseId: exerciseId, reps: reps, atEpochMs: at);

  group('exercise library', () {
    test('adding assigns unique ids even within one microsecond', () async {
      final state = await TrainingState.load();

      final first = await state.addExercise('Bench', ExerciseKind.weighted);
      final second = await state.addExercise('Squat', ExerciseKind.weighted);

      expect(first.id, isNot(second.id));
      expect(state.exercises.length, 2);
      expect(state.exerciseById(first.id)!.name, 'Bench');
      expect(state.exerciseById('nope'), isNull);
    });

    test('updating an unknown exercise is a no-op', () async {
      final state = await TrainingState.load();
      final exercise = await state.addExercise('Bench', ExerciseKind.weighted);

      await state.updateExercise(exercise.copyWith(name: 'Incline'));
      await state.updateExercise(
        const SportExercise(id: 'gone', name: 'X', kind: ExerciseKind.reps),
      );

      expect(state.exercises.single.name, 'Incline');
    });

    test('duplicating copies name plus suffix and kind, with a fresh id', () async {
      final state = await TrainingState.load();
      final source = await state.addExercise('Bench', ExerciseKind.weighted);

      await state.duplicateExercise(source.id, ' (Kopie)');
      await state.duplicateExercise('gone', ' (Kopie)');

      expect(state.exercises.length, 2);
      expect(state.exercises.last.name, 'Bench (Kopie)');
      expect(state.exercises.last.kind, ExerciseKind.weighted);
      expect(state.exercises.last.id, isNot(source.id));
    });

    test('reorder and remove persist through a reload', () async {
      final state = await TrainingState.load();
      await state.addExercise('A', ExerciseKind.reps);
      await state.addExercise('B', ExerciseKind.reps);
      await state.addExercise('C', ExerciseKind.reps);

      await state.reorderExercises(0, 2);
      await state.removeExercise(state.exercises.first.id);
      await state.reload();

      expect(state.exercises.map((exercise) => exercise.name), ['C', 'A']);
    });
  });

  group('routines', () {
    test('items are added, edited, reordered and removed by index', () async {
      final state = await TrainingState.load();
      final routine = await state.addRoutine('Push');
      final bench = await state.addExercise('Bench', ExerciseKind.weighted);
      final squat = await state.addExercise('Squat', ExerciseKind.weighted);

      await state.addRoutineItem(routine.id, bench.id);
      await state.addRoutineItem(routine.id, squat.id);
      final first = state.routineById(routine.id)!.items.first;
      await state.updateRoutineItem(
        routine.id,
        0,
        first.copyWith(targetSets: 5, targetWeight: 60),
      );
      await state.reorderRoutineItems(routine.id, 0, 1);

      final items = state.routineById(routine.id)!.items;
      expect(items.map((item) => item.exerciseId), [squat.id, bench.id]);
      expect(items.last.targetSets, 5);
      expect(items.last.targetWeight, 60);

      await state.removeRoutineItem(routine.id, 0);
      expect(state.routineById(routine.id)!.items.single.exerciseId, bench.id);
    });

    test('an out-of-range index or unknown routine is ignored', () async {
      final state = await TrainingState.load();
      final routine = await state.addRoutine('Push');
      await state.addRoutineItem(routine.id, 'ex');
      final item = state.routineById(routine.id)!.items.single;

      await state.updateRoutineItem(routine.id, 9, item.copyWith(target: 99));
      await state.updateRoutineItem('gone', 0, item.copyWith(target: 99));
      await state.removeRoutineItem(routine.id, -1);
      await state.addRoutineItem('gone', 'ex');
      await state.reorderRoutineItems('gone', 0, 1);

      expect(state.routineById(routine.id)!.items.single.target, item.target);
    });

    test('renaming and duplicating keep the items but not their ids', () async {
      final state = await TrainingState.load();
      final routine = await state.addRoutine('Push');
      await state.addRoutineItem(routine.id, 'ex-1');

      await state.renameRoutine(routine.id, 'Pull');
      await state.renameRoutine('gone', 'Nope');
      await state.duplicateRoutine(routine.id, ' (Kopie)');
      await state.duplicateRoutine('gone', ' (Kopie)');

      expect(state.routines.first.name, 'Pull');
      expect(state.routines.last.name, 'Pull (Kopie)');
      expect(state.routines.last.items.single.exerciseId, 'ex-1');
      expect(
        state.routines.last.items.single.id,
        isNot(state.routines.first.items.single.id),
      );
    });

    test('routines reorder and remove', () async {
      final state = await TrainingState.load();
      final push = await state.addRoutine('Push');
      await state.addRoutine('Pull');

      await state.reorderRoutines(0, 1);
      expect(state.routines.map((routine) => routine.name), ['Pull', 'Push']);

      await state.removeRoutine(push.id);
      expect(state.routines.single.name, 'Pull');
    });
  });

  group('sessions', () {
    test('a session is added, edited in place and removed', () async {
      final state = await TrainingState.load();
      const session = WorkoutSession(
        id: 's1',
        routineId: 'r1',
        startedAtMs: 1000,
        sets: [],
      );

      await state.addSession(session);
      await state.updateSession(
        WorkoutSession(
          id: 's1',
          routineId: 'r1',
          startedAtMs: 1000,
          sets: [setLog('ex-1')],
        ),
      );
      await state.updateSession(
        const WorkoutSession(
          id: 'gone',
          routineId: 'r1',
          startedAtMs: 1,
          sets: [],
        ),
      );

      expect(state.sessions.single.sets, hasLength(1));

      await state.removeSession('s1');
      expect(state.sessions, isEmpty);
    });

    /// The id is the session's start, so the same workout finished on two
    /// devices carries ONE id. Appended beside itself it reads as two workouts —
    /// and deleting either takes both, because the logbook deletes by id.
    test('logging the same workout twice keeps one entry', () async {
      final state = await TrainingState.load();
      const first = WorkoutSession(
        id: 's1',
        routineId: 'r1',
        startedAtMs: 1000,
        sets: [],
      );
      final second = WorkoutSession(
        id: 's1',
        routineId: 'r1',
        startedAtMs: 1000,
        sets: [setLog('ex-1')],
      );

      await state.addSession(first);
      await state.addSession(second);

      expect(state.sessions, hasLength(1));
      expect(state.sessions.single.sets, hasLength(1));
    });

    test('the previous session is the newest earlier one of the same routine', () async {
      final state = await TrainingState.load();
      const older = WorkoutSession(id: 'a', routineId: 'r1', startedAtMs: 100, sets: []);
      const newer = WorkoutSession(id: 'b', routineId: 'r1', startedAtMs: 300, sets: []);
      const other = WorkoutSession(id: 'c', routineId: 'r2', startedAtMs: 200, sets: []);
      const current = WorkoutSession(id: 'd', routineId: 'r1', startedAtMs: 400, sets: []);

      await state.addSession(newer);
      await state.addSession(older);
      await state.addSession(other);
      await state.addSession(current);

      expect(state.previousSessionOf(current)!.id, 'b');
      expect(state.previousSessionOf(older), isNull);
    });

    test('lastSetFor reads the newest session that has that set index', () async {
      final state = await TrainingState.load();
      await state.addSession(
        WorkoutSession(
          id: 'a',
          routineId: 'r1',
          startedAtMs: 100,
          sets: [setLog('bench', reps: 8), setLog('bench', reps: 7)],
        ),
      );
      await state.addSession(
        WorkoutSession(
          id: 'b',
          routineId: 'r1',
          startedAtMs: 200,
          sets: [setLog('bench', reps: 10)],
        ),
      );

      expect(state.lastSetFor('r1', 'bench', 0)!.reps, 10);
      expect(state.lastSetFor('r1', 'bench', 1)!.reps, 7);
      expect(state.lastSetFor('r1', 'bench', 5), isNull);
      expect(state.lastSetFor('r1', 'squat', 0), isNull);
    });
  });

  group('the active workout', () {
    test('is persisted, restored on the next load and cleared', () async {
      final state = await TrainingState.load();

      await state.saveActiveWorkout(snapshot('r1'));
      expect((await TrainingState.load()).activeWorkout!.routineId, 'r1');

      await state.clearActiveWorkout();
      expect(state.activeWorkout, isNull);
      expect((await TrainingState.load()).activeWorkout, isNull);
    });

    /// The zombie: a workout finished in the web panel, logged there, but whose
    /// `clear` never reached the account (or this device). Resuming it would log
    /// the same workout again under the same id — two rows the logbook then
    /// deletes as one. Its session being in the logbook is proof it is over.
    test('one whose session is already logged is not resumed', () async {
      final state = await TrainingState.load();
      await state.saveActiveWorkout(snapshot('r1'));
      await state.addSession(
        const WorkoutSession(
          id: 'gk',
          routineId: 'r1',
          startedAtMs: 1000,
          sets: [],
        ),
      );

      expect((await TrainingState.load()).activeWorkout, isNull);
    });

    test('a reload deliberately leaves the active workout alone', () async {
      final state = await TrainingState.load();
      await state.saveActiveWorkout(snapshot('r1'));

      await state.reload();

      expect(state.activeWorkout!.routineId, 'r1');
    });

    test('a snapshot is run against its own embedded items', () async {
      final state = await TrainingState.load();
      const embedded = RoutineItem(id: 'i1', exerciseId: 'ex-remote');
      final local = await state.addRoutine('Local');
      await state.addRoutineItem(local.id, 'ex-local');

      final followed = state.routineForSnapshot(
        snapshot(local.id, items: const [embedded]),
      )!;
      expect(followed.items.single.exerciseId, 'ex-remote');
      expect(followed.name, 'Push');

      final legacy = state.routineForSnapshot(snapshot(local.id))!;
      expect(legacy.items.single.exerciseId, 'ex-local');

      expect(state.routineForSnapshot(snapshot('gone')), isNull);
    });

    test('the driving flag and the ended-elsewhere ack are plain toggles', () async {
      final state = await TrainingState.load();

      expect(state.drivingActiveWorkout, isFalse);
      state.driveActiveWorkout(true);
      expect(state.drivingActiveWorkout, isTrue);

      expect(state.endedElsewhere, isFalse);
      state.acknowledgeEndedElsewhere();
      expect(state.endedElsewhere, isFalse);
    });

    test('stopping a watcher that was never started is safe', () async {
      final state = await TrainingState.load();

      state.stopWatchingActiveWorkout();
      state.dispose();
    });
  });

  test('the exposed lists are unmodifiable', () async {
    final state = await TrainingState.load();

    expect(
      () => state.exercises.add(
        const SportExercise(id: 'x', name: 'x', kind: ExerciseKind.reps),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => state.routines.add(
        const SportRoutine(id: 'x', name: 'x', items: []),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => state.sessions.add(
        const WorkoutSession(id: 'x', routineId: 'x', startedAtMs: 0, sets: []),
      ),
      throwsUnsupportedError,
    );
  });
}
