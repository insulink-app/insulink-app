import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_store.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';

/// The notification-action isolate can't reach secure storage, so it buffers a
/// Confirm/Reject to a temp file that the service isolate drains. These exercise
/// the file hand-off end to end (record → apply) against an in-memory store.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  const store = SportStore();
  final decisionFile = File(
    '${Directory.systemTemp.path}/insulink_training_decisions',
  );

  CardioTraining training(String id) => CardioTraining(
    id: id,
    type: CardioType.bike,
    startMs: 1000,
    endMs: 2000,
    track: const [],
    distanceM: 500,
    detected: true,
  );

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    if (await decisionFile.exists()) {
      await decisionFile.delete();
    }
  });

  test('confirm moves the pending training to the confirmed list', () async {
    await store.savePendingTrainings([training('a')]);

    store.recordTrainingDecision('confirm', 'a');
    await store.applyTrainingDecisions();

    expect((await store.loadPendingTrainings()), isEmpty);
    expect((await store.loadTrainings()).map((t) => t.id), ['a']);
    expect(await decisionFile.exists(), isFalse);
  });

  test('reject drops the pending training without confirming it', () async {
    await store.savePendingTrainings([training('b')]);

    store.recordTrainingDecision('reject', 'b');
    await store.applyTrainingDecisions();

    expect((await store.loadPendingTrainings()), isEmpty);
    expect((await store.loadTrainings()), isEmpty);
    expect(await decisionFile.exists(), isFalse);
  });

  test('confirm via the payload-embedded file path is drained', () async {
    await store.savePendingTrainings([training('d')]);

    // Mirrors the action-tap isolate: write to the path the notification carried
    // (decisionFilePath), which the drain then reads.
    store.recordTrainingDecision(
      'confirm',
      'd',
      filePath: store.decisionFilePath,
    );
    await store.applyTrainingDecisions();

    expect((await store.loadPendingTrainings()), isEmpty);
    expect((await store.loadTrainings()).map((t) => t.id), ['d']);
  });

  test('applyTrainingDecisions is a no-op when nothing was recorded', () async {
    await store.savePendingTrainings([training('c')]);

    await store.applyTrainingDecisions();

    expect((await store.loadPendingTrainings()).map((t) => t.id), ['c']);
  });
}
