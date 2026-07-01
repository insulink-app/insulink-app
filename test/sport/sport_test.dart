import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/activity/step_baseline.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';

void main() {
  group('WeightEntry round-trip', () {
    test('survives encode → decode', () {
      const entry = WeightEntry(atEpochMs: 1719700000000, kg: 72.5);
      final back = WeightEntry.fromJson(entry.toJson());
      expect(back.atEpochMs, entry.atEpochMs);
      expect(back.kg, entry.kg);
    });
  });

  group('StepBaseline', () {
    const base = StepBaseline(date: '2026-6-30', counter: 1000);

    test('same day subtracts the baseline counter', () {
      final result = base.update('2026-6-30', 1500);
      expect(result.today, 500);
      expect(result.baseline.counter, 1000);
    });

    test('reboot (counter drops) resets the baseline, today = 0', () {
      final result = base.update('2026-6-30', 200);
      expect(result.today, 0);
      expect(result.baseline.counter, 200);
    });

    test('new day resets the baseline, today = 0', () {
      final result = base.update('2026-7-1', 1100);
      expect(result.today, 0);
      expect(result.baseline.counter, 1100);
      expect(result.baseline.date, '2026-7-1');
    });
  });

  group('Routine/session round-trip', () {
    test('SportRoutine survives encode → decode', () {
      const routine = SportRoutine(
        id: 'r1',
        name: 'Push',
        items: [
          RoutineItem(
            id: 'i1',
            exerciseId: 'e1',
            targetSets: 4,
            target: 8,
            targetWeight: 20,
            restSeconds: 90,
          ),
        ],
      );
      final back = SportRoutine.fromJson(routine.toJson());
      expect(back.name, 'Push');
      expect(back.items.single.targetSets, 4);
      expect(back.items.single.targetWeight, 20);
    });

    test('WorkoutSession survives encode → decode', () {
      const session = WorkoutSession(
        id: 's1',
        routineId: 'r1',
        startedAtMs: 100,
        sets: [
          SetLog(exerciseId: 'e1', reps: 12, weightKg: 20, atEpochMs: 200),
        ],
      );
      final back = WorkoutSession.fromJson(session.toJson());
      expect(back.sets.single.reps, 12);
      expect(back.sets.single.weightKg, 20);
    });
  });

  group('RoutineItem id (reorder key)', () {
    test('preserves a stored id', () {
      const item = RoutineItem(id: 'keep', exerciseId: 'e1');
      expect(RoutineItem.fromJson(item.toJson()).id, 'keep');
    });

    test('migrates legacy items without an id to a non-empty unique one', () {
      final legacy = {
        'ex': 'e1',
        'sets': 3,
        'target': 10,
        'weight': 0,
        'rest': 60,
      };
      final first = RoutineItem.fromJson(Map.of(legacy)).id;
      final second = RoutineItem.fromJson(Map.of(legacy)).id;
      expect(first, isNotEmpty);
      expect(first, isNot(second));
    });
  });

  group('reorder semantics (onReorderItem)', () {
    // onReorderItem already delivers a corrected newIndex; the move is a pure
    // removeAt→insert. This test locks in the ordering logic.
    test('moving item 0 to index 2 reorders correctly', () {
      final items = ['a', 'b', 'c'];
      items.insert(2, items.removeAt(0));
      expect(items, ['b', 'c', 'a']);
    });
  });

  group('DailyActivity round-trip', () {
    test('survives encode → decode', () {
      const day = DailyActivity(
        dateKey: '2026-07-01',
        steps: 8000,
        distanceKm: 6.2,
        calories: 320,
      );
      final back = DailyActivity.fromJson(day.toJson());
      expect(back.dateKey, '2026-07-01');
      expect(back.steps, 8000);
      expect(back.calories, 320);
    });
  });

  group('WorkoutRunner', () {
    test('logs one set per completion and finishes after the last set', () {
      const exercise = SportExercise(
        id: 'e1',
        name: 'Squat',
        kind: ExerciseKind.reps,
      );
      const routine = SportRoutine(
        id: 'r1',
        name: 'Legs',
        // restSeconds: 0 ⇒ keine zeitgesteuerte Pause, deterministisch testbar.
        items: [
          RoutineItem(
            id: 'i1',
            exerciseId: 'e1',
            targetSets: 2,
            target: 10,
            restSeconds: 0,
          ),
        ],
      );
      WorkoutSession? finished;
      final runner = WorkoutRunner(routine, [exercise])
        ..onFinished = (session) => finished = session;

      runner.completeSet();
      expect(runner.phase, WorkoutPhase.exercising);
      expect(finished, isNull);

      runner.completeSet();
      expect(runner.phase, WorkoutPhase.done);
      expect(finished, isNotNull);
      expect(finished!.sets.length, 2);
      expect(finished!.sets.first.reps, 10);

      runner.dispose();
    });
  });
}
