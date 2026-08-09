import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_store.dart';
import 'package:insulink/src/sport/sport_sync.dart';

import '../support/secure_storage_mock.dart';

/// The pulls REPLACE a collection with the account's copy. While a local change
/// is still queued for upload, that copy is known to be out of date — adopting
/// it reverts the change (a just-confirmed training vanishing again).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);
  tearDown(SportSync.cancelPending);

  test('an untouched collection adopts the account copy', () {
    expect(SportSync().localWins('trainings'), isFalse);
  });

  test('a queued push makes the local copy win', () {
    SportSync().pushTrainings();
    expect(SportSync().localWins('trainings'), isTrue);
  });

  test('the guard is per collection, not global', () {
    SportSync().pushTrainings();
    expect(SportSync().localWins('trainings'), isTrue);
    expect(SportSync().localWins('workouts'), isFalse);
    expect(SportSync().localWins('exercises'), isFalse);
  });

  test('every pushed collection guards its own pull', () {
    SportSync()
      ..pushMeasurements()
      ..pushExercises()
      ..pushRoutines()
      ..pushWorkouts()
      ..pushTrainings();
    for (final collection in [
      'measurements',
      'exercises',
      'routines',
      'workouts',
      'trainings',
    ]) {
      expect(
        SportSync().localWins(collection),
        isTrue,
        reason: '$collection must not be overwritten while its push is queued',
      );
    }
  });

  /// The stamp fences a push that carries a workout on ("I last saw the account
  /// at this version"). Sending it for a DIFFERENT workout claims to continue one
  /// this device never saw, and the account refuses that — for as long as the
  /// workout runs, so the phone would work out alone with nothing reaching the
  /// panel. A workout this device is starting must therefore always send 0.
  test('a stamp is only ever sent for the workout it was taken from', () {
    expect(SportSync.stampFor(1000), 0);
    expect(SportSync.stampFor(2000), 0);
  });

  /// The account's confirmation is what tells a workout it has ENDED from one it
  /// has never heard of. Held in memory only, it was gone after a restart — and a
  /// workout ended in the web panel then ran on in the app for as long as the app
  /// lived, because every poll's "nothing runs" read as "the account never knew
  /// this one". Finishing it there logged the session a second time under the
  /// same id.
  test('the account confirmation survives a restart', () async {
    await const SportStore().saveWorkoutStamp(1000, 42);

    await SportSync.restoreStamp();

    expect(SportSync.confirmedActiveWorkoutStart, 1000);
    expect(SportSync.stampFor(1000), 42);
    expect(SportSync.stampFor(2000), 0);
  });

  test('a device that has never been confirmed restores nothing', () async {
    await SportSync.restoreStamp();

    expect(SportSync.confirmedActiveWorkoutStart, 0);
    expect(SportSync.stampFor(1000), 0);
  });

  test('cancelling the queued pushes releases the guard', () {
    SportSync().pushTrainings();
    SportSync.cancelPending();
    expect(SportSync().localWins('trainings'), isFalse);
  });
}
