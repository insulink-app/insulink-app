import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/logbook/workout_summary.dart';
import 'package:insulink/src/sport/sport_models.dart';

SetLog weighted(double kg, int reps, int atMs) =>
    SetLog(exerciseId: 'b', reps: reps, weightKg: kg, atEpochMs: atMs);

void main() {
  test('counts exercises/sets, sums effort as reps + held seconds', () {
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
    expect(summary.effort, 38); // 5 + 3 + 30
    expect(summary.durationSecs, 180); // (181000 - 1000) / 1000
  });

  test('empty session summarises to zeros without dividing an empty span', () {
    final summary = WorkoutSummary(
      WorkoutSession(id: 's', routineId: 'r', startedAtMs: 1000, sets: []),
    );

    expect(summary.sets, 0);
    expect(summary.exercises, 0);
    expect(summary.effort, 0);
    expect(summary.durationSecs, 0);
  });
}
