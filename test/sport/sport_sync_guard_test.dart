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

  /// The stamp fences a push that carries a workout on ("I last saw the account
  /// at this version"). Sending it for a DIFFERENT workout claims to continue one
  /// this device never saw, and the account refuses that — for as long as the
  /// workout runs, so the phone would work out alone with nothing reaching the
  /// panel. A workout this device is starting must therefore always send 0.
  test('a stamp is only ever sent for the workout it was taken from', () {
    expect(SportSync.stampFor(1000), 0);
    expect(SportSync.stampFor(2000), 0);
  });

  test('cancelling the queued pushes releases the guard', () {
    SportSync().pushTrainings();
    SportSync.cancelPending();
    expect(SportSync().localWins('trainings'), isFalse);
  });
}
