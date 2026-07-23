import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_store.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = SportStore();

  setUp(installSecureStorageMock);

  CardioTraining training(String id, {bool detected = false}) => CardioTraining(
    id: id,
    type: CardioType.jog,
    startMs: 1000,
    endMs: 2000,
    track: const [TrackPoint(lat: 50.1, lng: 8.6, tMs: 1500)],
    distanceM: 900,
    detected: detected,
  );

  test('the scalar settings fall back to their documented defaults', () async {
    expect(await store.loadStrideCm(), SportStore.defStrideCm);
    expect(await store.loadHeightCm(), SportStore.defHeightCm);
    expect(await store.loadStepsGoal(), SportStore.defStepsGoal);
    expect(await store.loadDistanceGoalM(), SportStore.defDistanceGoalM);
    expect(await store.loadCaloriesGoal(), SportStore.defCaloriesGoal);
    expect(await store.loadWeightGoalKg(), SportStore.defWeightGoalKg);
    expect(await store.loadDetectWatermark(), isNull);
    expect(await store.loadStepsBaseline(), isNull);
  });

  test('the scalar settings round-trip', () async {
    await store.saveStrideCm(82);
    await store.saveHeightCm(181);
    await store.saveStepsGoal(12000);
    await store.saveDistanceGoalM(8500);
    await store.saveCaloriesGoal(700);
    await store.saveWeightGoalKg(74.5);
    await store.saveDetectWatermark(1234567);
    await store.saveStepsBaseline('2026-07-09', 4200);

    expect(await store.loadStrideCm(), 82);
    expect(await store.loadHeightCm(), 181);
    expect(await store.loadStepsGoal(), 12000);
    expect(await store.loadDistanceGoalM(), 8500);
    expect(await store.loadCaloriesGoal(), 700);
    expect(await store.loadWeightGoalKg(), 74.5);
    expect(await store.loadDetectWatermark(), 1234567);
    expect(await store.loadStepsBaseline(), (date: '2026-07-09', counter: 4200));
  });

  test('an empty list key loads as empty, not as a crash', () async {
    expect(await store.loadWeights(), isEmpty);
    expect(await store.loadTrainings(), isEmpty);
    expect(await store.loadPendingTrainings(), isEmpty);
    expect(await store.loadLocationLog(), isEmpty);
    expect(await store.loadActivityLog(), isEmpty);
    expect(await store.loadActiveWorkout(), isNull);
    expect(await store.loadActiveTraining(), isNull);
  });

  test('trainings round-trip with their track and the auto flag', () async {
    await store.saveTrainings([training('a', detected: true)]);

    final loaded = (await store.loadTrainings()).single;
    expect(loaded.id, 'a');
    expect(loaded.type, CardioType.jog);
    expect(loaded.detected, isTrue);
    expect(loaded.track.single.lat, 50.1);
    expect(loaded.distanceM, 900);
  });

  test('the training list is capped to the most recent entries', () async {
    await store.saveTrainings([
      for (var index = 0; index < 505; index++) training('t$index'),
    ]);

    final loaded = await store.loadTrainings();
    expect(loaded.length, 500);
    expect(loaded.first.id, 't5');
  });

  test('confirming a pending training moves it to the confirmed list', () async {
    await store.savePendingTrainings([training('a'), training('b')]);

    await store.confirmPendingTraining('a');

    expect((await store.loadTrainings()).single.id, 'a');
    expect((await store.loadPendingTrainings()).single.id, 'b');
  });

  test('confirming an unknown id changes nothing', () async {
    await store.savePendingTrainings([training('a')]);

    await store.confirmPendingTraining('gone');

    expect(await store.loadTrainings(), isEmpty);
    expect((await store.loadPendingTrainings()).single.id, 'a');
  });

  test('rejecting a pending training just drops it', () async {
    await store.savePendingTrainings([training('a'), training('b')]);

    await store.rejectPendingTraining('a');

    expect((await store.loadPendingTrainings()).single.id, 'b');
    expect(await store.loadTrainings(), isEmpty);
  });

  test('the location log is a ring buffer keeping the newest points', () async {
    for (var index = 0; index < 3; index++) {
      await store.appendLocationSample(
        TrackPoint(lat: 50.0 + index, lng: 8.0, tMs: index),
      );
    }

    final log = await store.loadLocationLog();
    expect(log.length, 3);
    expect(log.last.lat, 52.0);
  });

  test('the activity log round-trips its recognised kinds', () async {
    await store.appendActivitySample(
      const ActivitySample(tMs: 10, kind: ActivityKind.bike),
    );
    await store.appendActivitySample(
      const ActivitySample(tMs: 20, kind: ActivityKind.vehicle),
    );

    final log = await store.loadActivityLog();
    expect(log.map((sample) => sample.kind), [
      ActivityKind.bike,
      ActivityKind.vehicle,
    ]);
  });

  group('the notification decision hand-off file', () {
    setUp(() async {
      final file = File(store.decisionFilePath);
      if (await file.exists()) {
        await file.delete();
      }
    });

    tearDown(() async {
      final file = File(store.decisionFilePath);
      if (await file.exists()) {
        await file.delete();
      }
    });

    test('draining nothing is a cheap no-op', () async {
      expect(await store.applyTrainingDecisions(), isFalse);
    });

    test('a buffered confirm is applied and reported as pushable', () async {
      await store.savePendingTrainings([training('a'), training('b')]);
      store.recordTrainingDecision('confirm', 'a');
      store.recordTrainingDecision('reject', 'b');

      expect(await store.applyTrainingDecisions(), isTrue);
      expect((await store.loadTrainings()).single.id, 'a');
      expect(await store.loadPendingTrainings(), isEmpty);
      expect(File(store.decisionFilePath).existsSync(), isFalse);
    });

    test('a reject-only batch needs no backend push', () async {
      await store.savePendingTrainings([training('a')]);
      store.recordTrainingDecision('reject', 'a');

      expect(await store.applyTrainingDecisions(), isFalse);
      expect(await store.loadPendingTrainings(), isEmpty);
    });

    test('a malformed line is skipped instead of throwing', () async {
      File(store.decisionFilePath).writeAsStringSync('garbage\n');

      expect(await store.applyTrainingDecisions(), isFalse);
    });
  });
}
