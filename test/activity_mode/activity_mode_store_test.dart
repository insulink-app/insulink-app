import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/activity_mode/activity_mode.dart';
import 'package:insulink/src/activity_mode/activity_mode_settings.dart';
import 'package:insulink/src/activity_mode/activity_mode_store.dart';
import 'package:insulink/src/sport/sport_store.dart';
import 'package:insulink/src/sport/training/active_training.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 15, 17);
  const store = ActivityModeStore();
  const sport = SportStore();

  setUp(installSecureStorageMock);

  Future<void> startWorkout(DateTime startedAt) {
    return sport.saveActiveWorkout(
      WorkoutSnapshot(
        routineId: 'legs',
        startedAtMs: startedAt.millisecondsSinceEpoch,
        exerciseIndex: 0,
        setIndex: 0,
        phase: WorkoutPhase.exercising,
        setStartedAtMs: startedAt.millisecondsSinceEpoch,
        restEndsAtMs: null,
        restStartedAtMs: null,
        pausedTotalMs: 0,
        currentReps: 10,
        currentWeight: 40,
        sets: const [],
      ),
    );
  }

  Future<(ActivityMode, ActivityModeSource)> modeAt(DateTime at) async {
    final reading = await store.current(at);
    return (reading.mode, reading.source);
  }

  /// Switched off in the profile, nothing moves the loop: not a hand choice,
  /// not a workout, not a detected ride.
  test('switched off, every source is ignored', () async {
    await ActivityModeSettings.enabled.save(false);
    await store.choose(ActivityMode.strength, now);
    await startWorkout(now);
    await store.markDetected(true, now);

    expect(await modeAt(now), (ActivityMode.normal, ActivityModeSource.none));

    await ActivityModeSettings.enabled.save(true);

    expect(await modeAt(now), (
      ActivityMode.strength,
      ActivityModeSource.manual,
    ));
  });

  test('nothing going on is normal', () async {
    expect(await modeAt(now), (ActivityMode.normal, ActivityModeSource.none));
  });

  test(
    'a detected training is endurance until the sighting goes stale',
    () async {
      await store.markDetected(true, now);

      expect(await modeAt(now.add(const Duration(minutes: 5))), (
        ActivityMode.endurance,
        ActivityModeSource.detected,
      ));
      expect(await modeAt(now.add(const Duration(minutes: 11))), (
        ActivityMode.normal,
        ActivityModeSource.none,
      ));

      await store.markDetected(false, now);
      expect(await modeAt(now), (ActivityMode.normal, ActivityModeSource.none));
    },
  );

  test('a cardio recording is endurance', () async {
    await sport.saveActiveTraining(
      ActiveTraining(
        type: CardioType.bike,
        startMs: now.millisecondsSinceEpoch,
      ),
    );

    expect(await modeAt(now), (
      ActivityMode.endurance,
      ActivityModeSource.recording,
    ));
  });

  test('a running routine is strength, even during a detected walk', () async {
    await store.markDetected(true, now);
    await startWorkout(now.subtract(const Duration(minutes: 30)));

    expect(await modeAt(now), (
      ActivityMode.strength,
      ActivityModeSource.workout,
    ));
  });

  test('a routine left running for hours no longer counts', () async {
    await startWorkout(now.subtract(const Duration(hours: 5)));

    expect(await modeAt(now), (ActivityMode.normal, ActivityModeSource.none));
  });

  test(
    'a manual choice wins, lapses after two hours, and Auto ends it',
    () async {
      await startWorkout(now);
      await store.choose(ActivityMode.normal, now);

      final manual = await store.current(now.add(const Duration(minutes: 90)));
      expect(manual.mode, ActivityMode.normal);
      expect(manual.source, ActivityModeSource.manual);
      expect(manual.until, now.add(ActivityModeStore.manualFor));
      expect(await modeAt(now.add(const Duration(hours: 2))), (
        ActivityMode.strength,
        ActivityModeSource.workout,
      ));

      await store.choose(ActivityMode.endurance, now);
      await store.choose(null, now);
      expect(await modeAt(now), (
        ActivityMode.strength,
        ActivityModeSource.workout,
      ));
    },
  );
}
