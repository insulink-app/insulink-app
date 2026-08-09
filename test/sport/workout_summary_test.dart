import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/logbook/workout_summary.dart';
import 'package:insulink/src/sport/sport_models.dart';

SetLog weighted(double kg, int reps, int atMs) =>
    SetLog(exerciseId: 'b', reps: reps, weightKg: kg, atEpochMs: atMs);

void main() {
  test('counts exercises and sets and measures the span', () {
    final summary = WorkoutSummary(
      WorkoutSession(
        id: 's',
        routineId: 'r',
        startedAtMs: 1000,
        sets: [
          weighted(60, 5, 60000), // 5 reps
          weighted(80, 3, 120000), // 3 reps
          SetLog(exerciseId: 'p', seconds: 30, atEpochMs: 181000), // 30 s held
        ],
      ),
    );

    expect(summary.sets, 3);
    expect(summary.exercises, 2); // 'b' and 'p'
    expect(summary.durationSecs, 180); // (181000 - 1000) / 1000
  });

  /// The headline percentage is per exercise, then averaged — the whole point is
  /// that a high-rep exercise cannot decide it alone. Comparing the two sessions'
  /// summed effort instead would answer 0 % below, where every exercise was
  /// genuinely trained better.
  group('the change vs the previous session', () {
    SetLog reps(String exerciseId, int count) =>
        SetLog(exerciseId: exerciseId, reps: count, atEpochMs: 0);

    WorkoutSession sessionOf(List<SetLog> sets, {int startedAtMs = 0}) =>
        WorkoutSession(
          id: '$startedAtMs',
          routineId: 'r',
          startedAtMs: startedAtMs,
          sets: sets,
        );

    test('weighs every exercise the same, not by its rep count', () {
      final previous = sessionOf([reps('situps', 100), reps('bench', 5)]);
      final current = sessionOf([reps('situps', 90), reps('bench', 10)]);

      // situps 0.9, bench 2.0 → 1.45. By summed effort it would be 100/105.
      expect(effortRatioVsPrevious(current, previous), closeTo(1.45, 0.001));
    });

    test('ignores exercises only one of the two sessions has', () {
      final previous = sessionOf([reps('bench', 10), reps('dropped', 50)]);
      final current = sessionOf([reps('bench', 12), reps('new', 40)]);

      expect(effortRatioVsPrevious(current, previous), closeTo(1.2, 0.001));
    });

    test('two sessions sharing no exercise compare to nothing', () {
      final previous = sessionOf([reps('bench', 10)]);
      final current = sessionOf([reps('squat', 10)]);

      expect(effortRatioVsPrevious(current, previous), isNull);
    });
  });

  test('empty session summarises to zeros without dividing an empty span', () {
    final summary = WorkoutSummary(
      WorkoutSession(id: 's', routineId: 'r', startedAtMs: 1000, sets: []),
    );

    expect(summary.sets, 0);
    expect(summary.exercises, 0);
    expect(summary.durationSecs, 0);
  });
}
