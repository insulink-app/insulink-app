import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_store.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = SportStore();

  setUp(installSecureStorageMock);

  CardioTraining training(
    String id, {
    int startMs = 1000,
    bool detected = false,
  }) => CardioTraining(
    id: id,
    type: CardioType.jog,
    startMs: startMs,
    endMs: startMs + 60000,
    track: const [],
    distanceM: 500,
    detected: detected,
  );

  test('the average speed needs a recorded duration', () {
    final logged = training('a');
    expect(logged.duration, const Duration(minutes: 1));
    expect(logged.avgSpeedKmh, closeTo(30, 0.01));

    const instant = CardioTraining(
      id: 'a',
      type: CardioType.jog,
      startMs: 1000,
      endMs: 1000,
      track: [],
      distanceM: 500,
    );
    expect(instant.avgSpeedKmh, 0);
  });

  test('a fresh state has nothing stored, pending or running', () async {
    final state = await CardioTrainingState.load();

    expect(state.trainings, isEmpty);
    expect(state.pendingTrainings, isEmpty);
    expect(state.activeTraining, isNull);
    expect(await state.activeTrack(), isEmpty);
  });

  test('trainings are kept ascending by start time', () async {
    final state = await CardioTrainingState.load();

    await state.addTraining(training('b', startMs: 3000));
    await state.addTraining(training('a', startMs: 1000));

    expect((await CardioTrainingState.load()).trainings.map((t) => t.id), [
      'a',
      'b',
    ]);
  });

  test('pending detections are listed newest first', () async {
    await store.savePendingTrainings([
      training('old', startMs: 1000, detected: true),
      training('new', startMs: 2000, detected: true),
    ]);

    final state = await CardioTrainingState.load();

    expect(state.pendingTrainings.map((t) => t.id), ['new', 'old']);
  });

  test('confirming a detection moves it into the trainings', () async {
    await store.savePendingTrainings([
      training('a', startMs: 5000, detected: true),
      training('b', startMs: 1000, detected: true),
    ]);
    final state = await CardioTrainingState.load();

    await state.confirmDetected('a');

    expect(state.trainings.single.id, 'a');
    expect(state.pendingTrainings.single.id, 'b');
    expect((await store.loadTrainings()).single.id, 'a');
  });

  test('confirming an unknown detection is a no-op', () async {
    await store.savePendingTrainings([training('a', detected: true)]);
    final state = await CardioTrainingState.load();

    await state.confirmDetected('gone');

    expect(state.trainings, isEmpty);
    expect(state.pendingTrainings, hasLength(1));
  });

  test('rejecting a detection drops it from the store too', () async {
    await store.savePendingTrainings([training('a', detected: true)]);
    final state = await CardioTrainingState.load();

    await state.rejectDetected('a');

    expect(state.pendingTrainings, isEmpty);
    expect(await store.loadPendingTrainings(), isEmpty);
  });

  test('reloadPending adopts what the service isolate wrote', () async {
    final state = await CardioTrainingState.load();
    await store.savePendingTrainings([training('p', detected: true)]);
    await store.saveTrainings([training('t', startMs: 9000)]);

    await state.reloadPending();

    expect(state.pendingTrainings.single.id, 'p');
    expect(state.trainings.single.id, 't');
  });

  test('the type of a logged training can be corrected afterwards', () async {
    final state = await CardioTrainingState.load();
    await state.addTraining(training('a'));

    await state.changeTrainingType('a', CardioType.bike);
    await state.changeTrainingType('gone', CardioType.walk);

    expect(state.trainings.single.type, CardioType.bike);
  });

  test('removing a training persists the shorter list', () async {
    final state = await CardioTrainingState.load();
    await state.addTraining(training('a'));

    await state.removeTraining('a');

    expect(state.trainings, isEmpty);
    expect(await store.loadTrainings(), isEmpty);
  });

  group('the live recording', () {
    test('start/pause/resume survive an app restart', () async {
      final state = await CardioTrainingState.load();

      await state.startTraining(CardioType.bike);
      expect(state.activeTraining!.type, CardioType.bike);
      expect(state.activeTraining!.isPaused, isFalse);

      await state.pauseTraining();
      expect(state.activeTraining!.isPaused, isTrue);
      await state.pauseTraining();
      expect(
        state.activeTraining!.isPaused,
        isTrue,
        reason: 'pausing twice is a no-op',
      );

      expect(
        (await CardioTrainingState.load()).activeTraining!.isPaused,
        isTrue,
      );

      await state.resumeTraining();
      expect(state.activeTraining!.isPaused, isFalse);
      await state.resumeTraining();
      expect(state.activeTraining!.isPaused, isFalse);
    });

    test('pause/resume/stop without a running training do nothing', () async {
      final state = await CardioTrainingState.load();

      await state.pauseTraining();
      await state.resumeTraining();
      await state.stopTraining();

      expect(state.activeTraining, isNull);
      expect(state.trainings, isEmpty);
    });

    test('the active track is the log slice since the start', () async {
      final state = await CardioTrainingState.load();
      await state.startTraining(CardioType.walk);
      final start = state.activeTraining!.startMs;

      await store.appendLocationSample(
        TrackPoint(lat: 50.0, lng: 8.0, tMs: start - 60000),
      );
      await store.appendLocationSample(
        TrackPoint(lat: 50.1, lng: 8.0, tMs: start + 1000),
      );

      final track = await state.activeTrack();
      expect(track.single.lat, 50.1);
    });

    test('stopping logs a training with the recorded distance', () async {
      final state = await CardioTrainingState.load();
      await state.startTraining(CardioType.walk);
      final start = state.activeTraining!.startMs;
      await store.appendLocationSample(
        TrackPoint(lat: 50.0, lng: 8.0, tMs: start + 1000),
      );
      await store.appendLocationSample(
        TrackPoint(lat: 50.01, lng: 8.0, tMs: start + 2000),
      );

      await state.stopTraining();

      expect(state.activeTraining, isNull);
      expect(await store.loadActiveTraining(), isNull);
      final logged = state.trainings.single;
      expect(logged.type, CardioType.walk);
      expect(logged.track, hasLength(2));
      expect(logged.distanceM, closeTo(1112, 5));
    });
  });

  test(
    'a training is found whether it is confirmed or still pending',
    () async {
      await store.saveTrainings([training('done')]);
      await store.savePendingTrainings([training('detected', detected: true)]);
      final state = await CardioTrainingState.load();

      expect(state.trainingById('done')!.id, 'done');
      expect(state.trainingById('detected')!.id, 'detected');
      expect(state.trainingById('gone'), isNull);
      expect(state.isPending('detected'), isTrue);
      expect(state.isPending('done'), isFalse);
    },
  );

  test('the exposed lists are unmodifiable', () async {
    final state = await CardioTrainingState.load();

    expect(() => state.trainings.add(training('x')), throwsUnsupportedError);
    expect(
      () => state.pendingTrainings.add(training('x')),
      throwsUnsupportedError,
    );
  });
}
