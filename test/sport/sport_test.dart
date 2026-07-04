import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/activity/step_baseline.dart';
import 'package:insulink/src/sport/routines/routine_duration.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_store.dart';
import 'package:insulink/src/sport/training/active_training.dart';
import 'package:insulink/src/sport/training/cardio_detector.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';

void main() {
  group('German number formatting', () {
    test('thousands use "." and decimals use ","', () {
      expect(sportInt(1234), '1.234');
      expect(sportInt(8000), '8.000');
      expect(sportDecimal(6.2, 2), '6,20');
      expect(sportDecimal(72.5, 1), '72,5');
    });
  });

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

  group('estimatedRoutineMinutes', () {
    test('sets × (60 s work + rest), rounded to minutes', () {
      const exercise = SportExercise(
        id: 'e1',
        name: 'Squat',
        kind: ExerciseKind.reps,
      );
      const routine = SportRoutine(
        id: 'r1',
        name: 'Legs',
        items: [
          RoutineItem(
            id: 'i1',
            exerciseId: 'e1',
            targetSets: 3,
            target: 10,
            restSeconds: 60,
          ),
        ],
      );
      // 3 × (60 + 60) = 360 s = 6 min.
      expect(estimatedRoutineMinutes(routine, [exercise]), 6);
    });
  });

  group('CardioDetector', () {
    test('recognises a ~10 km/h jog surrounded by standing still', () {
      final points = <TrackPoint>[];
      var time = 1000000000000;
      var lat = 52.0;
      // ~166 m north per minute ≈ 10 km/h.
      const stepLat = 166 / 111320;
      void add() {
        points.add(TrackPoint(lat: lat, lng: 13.0, tMs: time));
        time += 60000;
      }

      for (var i = 0; i < 6; i++) {
        add();
      }
      for (var i = 0; i < 21; i++) {
        add();
        lat += stepLat;
      }
      for (var i = 0; i < 3; i++) {
        add();
      }

      final detected = const CardioDetector().detect(points);
      expect(detected.length, 1);
      expect(detected.single.type, CardioType.jog);
      expect(detected.single.detected, isTrue);
      expect(detected.single.distanceM, greaterThan(3000));
    });

    test('ignores standing still', () {
      final points = [
        for (var i = 0; i < 10; i++)
          TrackPoint(lat: 52.0, lng: 13.0, tMs: 1000000000000 + i * 60000),
      ];
      expect(const CardioDetector().detect(points), isEmpty);
    });

    // Builds a ride: [moving minutes] + [stationary minutes] + [moving minutes],
    // one point per minute, ~24 km/h while moving.
    List<TrackPoint> ride(int moveA, int stopMinutes, int moveB) {
      final points = <TrackPoint>[];
      var time = 1000000000000;
      var lat = 52.0;
      const stepLat = 400 / 111320; // ~400 m/min ≈ 24 km/h
      void add() {
        points.add(TrackPoint(lat: lat, lng: 13.0, tMs: time));
        time += 60000;
      }

      for (var i = 0; i < moveA; i++) {
        add();
        lat += stepLat;
      }
      for (var i = 0; i < stopMinutes; i++) {
        add();
      }
      for (var i = 0; i < moveB; i++) {
        add();
        lat += stepLat;
      }
      return points;
    }

    test('a 2-min stop (crossing) keeps the ride as ONE training', () {
      final detected = const CardioDetector().detect(ride(12, 2, 12));
      expect(detected.length, 1);
      expect(detected.single.type, CardioType.bike);
    });

    test('a long stop (> tolerance) splits into two trainings', () {
      final detected = const CardioDetector().detect(ride(12, 5, 12));
      expect(detected.length, 2);
    });

    test('a vehicle-tagged fast segment is discarded (bus/train, not bike)', () {
      final points = ride(12, 0, 12);
      final log = [
        ActivitySample(tMs: points.first.tMs, kind: ActivityKind.vehicle),
      ];
      expect(const CardioDetector().detect(points, log), isEmpty);
    });

    test('a bike-tagged fast segment stays a bike ride', () {
      final points = ride(12, 0, 12);
      final log = [
        ActivitySample(tMs: points.first.tMs, kind: ActivityKind.bike),
      ];
      final detected = const CardioDetector().detect(points, log);
      expect(detected.length, 1);
      expect(detected.single.type, CardioType.bike);
    });
  });

  group('ActiveTraining', () {
    test('round-trips through JSON and pause/resume', () {
      const active = ActiveTraining(
        type: CardioType.bike,
        startMs: 1000,
        pausedTotalMs: 500,
      );
      final back = ActiveTraining.fromJson(active.toJson());
      expect(back.type, CardioType.bike);
      expect(back.startMs, 1000);
      expect(back.pausedTotalMs, 500);
      expect(back.isPaused, isFalse);
      expect(active.pause().isPaused, isTrue);
      expect(active.pause().resume().isPaused, isFalse);
    });
  });

  group('TrainingState.lastSetFor', () {
    TrainingState state(List<WorkoutSession> sessions) =>
        TrainingState(const SportStore(), const [], const [], sessions, null);

    test('returns the newest matching set, falling back to older sessions', () {
      const older = WorkoutSession(
        id: 's1',
        routineId: 'r1',
        startedAtMs: 1,
        sets: [
          SetLog(exerciseId: 'e1', reps: 8, atEpochMs: 1),
          SetLog(exerciseId: 'e1', reps: 9, atEpochMs: 2),
        ],
      );
      const newer = WorkoutSession(
        id: 's2',
        routineId: 'r1',
        startedAtMs: 3,
        sets: [SetLog(exerciseId: 'e1', reps: 12, atEpochMs: 3)],
      );
      final training = state([older, newer]);
      expect(training.lastSetFor('e1', 0)?.reps, 12);
      expect(training.lastSetFor('e1', 1)?.reps, 9);
      expect(training.lastSetFor('e1', 2), isNull);
    });
  });

  group('WorkoutRunner controls', () {
    const exercise = SportExercise(
      id: 'e1',
      name: 'Squat',
      kind: ExerciseKind.reps,
    );
    SportRoutine routineWithRest(int rest, {int exercises = 1}) => SportRoutine(
      id: 'r1',
      name: 'R',
      items: [
        for (var i = 0; i < exercises; i++)
          RoutineItem(
            id: 'i$i',
            exerciseId: 'e1',
            targetSets: 2,
            target: 10,
            restSeconds: rest,
          ),
      ],
    );

    test('snapshot resumes the same state', () {
      final routine = routineWithRest(0);
      WorkoutSnapshot? snapshot;
      final runner = WorkoutRunner(routine, [
        exercise,
      ], onPersist: (snap) => snapshot = snap);
      runner.completeSet();
      expect(snapshot, isNotNull);
      // round-trips through JSON like the store does.
      final restored = WorkoutRunner(routine, [
        exercise,
      ], resume: WorkoutSnapshot.fromJson(snapshot!.toJson()));
      expect(restored.setNumber, 2);
      expect(restored.lastLoggedSet?.reps, 10);
      runner.dispose();
      restored.dispose();
    });

    test('extendRest adds time to the rest', () {
      final runner = WorkoutRunner(routineWithRest(2), [exercise]);
      runner.completeSet();
      expect(runner.phase, WorkoutPhase.resting);
      runner.extendRest(60);
      expect(runner.restRemaining.inSeconds, greaterThan(50));
      runner.dispose();
    });

    test('pause freezes and resume clears', () {
      final runner = WorkoutRunner(routineWithRest(0), [exercise]);
      runner.pause();
      expect(runner.isPaused, isTrue);
      final first = runner.sessionElapsed;
      final second = runner.sessionElapsed;
      expect(first, second);
      runner.resume();
      expect(runner.isPaused, isFalse);
      runner.dispose();
    });

    test('jumpTo switches exercise and resets to its first set', () {
      final runner = WorkoutRunner(routineWithRest(0, exercises: 3), [
        exercise,
      ]);
      runner.jumpTo(2);
      expect(runner.exerciseIndex, 2);
      expect(runner.setNumber, 1);
      expect(runner.phase, WorkoutPhase.exercising);
      runner.dispose();
    });
  });
}
