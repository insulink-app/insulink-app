import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_store.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';

import '../support/secure_storage_mock.dart';

/// An auto-detected training is a question, and a question nobody can answer any
/// more has to stop being asked: a day later the user cannot honestly say
/// whether that hour was a run, and an undecided prompt would sit on the sport
/// page for good.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = SportStore();

  late Map<String, String> backing;

  setUp(() {
    backing = installSecureStorageMock();
  });

  CardioTraining detected(String id, Duration ago) {
    final end = DateTime.now().subtract(ago).millisecondsSinceEpoch;
    return CardioTraining(
      id: id,
      type: CardioType.jog,
      startMs: end - 1800000,
      endMs: end,
      track: const [],
      distanceM: 5000,
      detected: true,
    );
  }

  int storedCount() {
    final raw = backing['sport.pending_trainings'];
    return raw == null ? 0 : (jsonDecode(raw) as List).length;
  }

  test('a detection older than a day is not offered any more', () async {
    await store.savePendingTrainings([
      detected('stale', const Duration(hours: 25)),
      detected('fresh', const Duration(hours: 23)),
    ]);
    final pending = await store.loadPendingTrainings();
    expect(pending.map((training) => training.id), ['fresh']);
  });

  test('the lapsed one is gone from the sport page too', () async {
    await store.savePendingTrainings([
      detected('stale', const Duration(days: 3)),
    ]);
    final state = await CardioTrainingState.load();
    expect(state.pendingTrainings, isEmpty);
    expect(state.isPending('stale'), isFalse);
  });

  test('the next decision writes the lapsed one out of storage', () async {
    await store.savePendingTrainings([
      detected('stale', const Duration(hours: 30)),
      detected('fresh', const Duration(minutes: 5)),
    ]);
    expect(storedCount(), 2);
    await store.rejectPendingTraining('fresh');
    expect(storedCount(), 0);
  });
}
