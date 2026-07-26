import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_sync.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';

import '../support/http_mock.dart';
import '../support/secure_storage_mock.dart';

/// What the phone does with the account's answer — the one step between the two
/// screens that no other test covers, and the one this feature kept breaking in:
/// the workout reaches storage but never the live state, or a change made on the
/// other device is dismissed as "our own copy coming back".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
    SportSync.cancelPending();
  });
  tearDown(SportSync.cancelPending);

  Map<String, Object?> snapshot({int? pausedAt, int set = 0}) => {
    'routine': 'r1',
    'name': 'Push',
    'items': [
      {
        'id': 'i1',
        'ex': 'bench',
        'sets': 3,
        'target': 10,
        'weight': 40.0,
        'rest': 60,
      },
    ],
    'started': 1000,
    'ex': 0,
    'set': set,
    'phase': 'exercising',
    'setStarted': 1000,
    'restEnds': null,
    'restStarted': null,
    'paused': 0,
    'pausedAt': pausedAt,
    'reps': 10,
    'weight': 40.0,
    'sets': <Object?>[],
  };

  /// One poll against an account holding [workout], stamped [updated].
  Future<TrainingState> polled(
    FakeHttp http,
    TrainingState state,
  ) async {
    await http.run(() async {
      state.watchActiveWorkout();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      state.stopWatchingActiveWorkout();
    });
    return state;
  }

  test('a workout on the account reaches the live state, not just storage', () async {
    final http = FakeHttp({
      '/sport/workout/active/find/': {
        'success': true,
        'workout': snapshot(),
        'updated': 500,
      },
    });
    final state = await TrainingState.load();

    await polled(http, state);

    expect(state.activeWorkout, isNotNull);
    expect(state.activeWorkout!.routineId, 'r1');
    state.dispose();
  });

  test('a pause made on the other device is adopted', () async {
    final http = FakeHttp({
      '/sport/workout/active/find/': {
        'success': true,
        'workout': snapshot(pausedAt: 7000),
        'updated': 500,
      },
    });
    final state = await TrainingState.load();

    await polled(http, state);

    expect(state.activeWorkout!.pausedAtMs, 7000);
    expect(
      WorkoutRunner(
        state.routineForSnapshot(state.activeWorkout!)!,
        const [],
        resume: state.activeWorkout,
      ).isPaused,
      isTrue,
      reason: 'the runner the page rebuilds must come up paused',
    );
    state.dispose();
  });

  /// The open runner rebuilds itself whenever the shared state holds a snapshot
  /// other than the one it published, compared by identity — so an unchanged poll
  /// must leave that very object in place.
  test('our own copy coming back is not adopted again', () async {
    final http = FakeHttp({
      '/sport/workout/active/find/': {
        'success': true,
        'workout': snapshot(),
        'updated': 500,
      },
    });
    final state = await TrainingState.load();

    await polled(http, state);
    final adopted = state.activeWorkout;
    await polled(http, state);

    expect(identical(state.activeWorkout, adopted), isTrue);
    state.dispose();
  });

  /// The stamp is the whole ordering: a snapshot the account gained AFTER this
  /// device last saw it must be adopted, however small the change.
  test('a later stamp is adopted even when only the pause changed', () async {
    final running = FakeHttp({
      '/sport/workout/active/find/': {
        'success': true,
        'workout': snapshot(),
        'updated': 500,
      },
    });
    final state = await TrainingState.load();
    await polled(running, state);
    final first = state.activeWorkout;

    final paused = FakeHttp({
      '/sport/workout/active/find/': {
        'success': true,
        'workout': snapshot(pausedAt: 7000),
        'updated': 501,
      },
    });
    await polled(paused, state);

    expect(state.activeWorkout!.pausedAtMs, 7000);
    expect(identical(state.activeWorkout, first), isFalse);
    state.dispose();
  });

  /// A push must carry the stamp of the copy this device last saw, so the
  /// account can refuse one that carries on a workout somebody already ended.
  test('a push carries the stamp of the workout it belongs to', () async {
    final http = FakeHttp({
      '/sport/workout/active/find/': {
        'success': true,
        'workout': snapshot(),
        'updated': 500,
      },
      '/sport/workout/active/sync/': {'success': true, 'updated': 501},
    });
    final state = await TrainingState.load();
    await polled(http, state);

    await http.run(() async {
      await state.saveActiveWorkout(
        WorkoutSnapshot.fromJson(snapshot(pausedAt: 8000).cast()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });

    final push = http.lastTo('/sport/workout/active/sync/')!;
    expect(push['updated'], 500);
    expect((push['workout'] as Map)['pausedAt'], 8000);
    state.dispose();
  });

  /// The phone starts the routine, and the runner's first poll goes out before
  /// its own push has left the debounce. The account answering "nothing runs" is
  /// then not an ending — it has never heard of this workout. Wiping it there
  /// leaves the runner going over a session the shared state has forgotten, and
  /// nothing syncs for the rest of the workout.
  test('a workout started here survives a poll that beat its push', () async {
    final empty = FakeHttp({
      '/sport/workout/active/find/': {'success': true},
    });
    final state = await TrainingState.load();
    state.driveActiveWorkout(true);
    await state.saveActiveWorkout(
      WorkoutSnapshot.fromJson(snapshot().cast()),
    );

    await polled(empty, state);

    expect(state.activeWorkout, isNotNull);
    expect(state.endedElsewhere, isFalse);
    state.dispose();
  });

  test('a workout the account confirmed and then dropped does end', () async {
    final running = FakeHttp({
      '/sport/workout/active/find/': {
        'success': true,
        'workout': snapshot(),
        'updated': 500,
      },
    });
    final state = await TrainingState.load();
    state.driveActiveWorkout(true);
    await polled(running, state);

    await polled(FakeHttp({'/sport/workout/active/find/': {'success': true}}), state);

    expect(state.activeWorkout, isNull);
    expect(state.endedElsewhere, isTrue);
    state.dispose();
  });

  test('an unreachable account does not end the workout', () async {
    final http = FakeHttp({
      '/sport/workout/active/find/': {
        'success': true,
        'workout': snapshot(),
        'updated': 500,
      },
    });
    final state = await TrainingState.load();
    await polled(http, state);

    await polled(FakeHttp(const {}), state);

    expect(state.activeWorkout, isNotNull);
    state.dispose();
  });
}
