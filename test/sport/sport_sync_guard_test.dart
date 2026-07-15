import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_sync.dart';

/// The pulls REPLACE a collection with the account's copy. While a local change
/// is still queued for upload, that copy is known to be out of date — adopting
/// it reverts the change (a just-confirmed training vanishing again).
void main() {
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

  test('cancelling the queued pushes releases the guard', () {
    SportSync().pushTrainings();
    SportSync.cancelPending();
    expect(SportSync().localWins('trainings'), isFalse);
  });
}
