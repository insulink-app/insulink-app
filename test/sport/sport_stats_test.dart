import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/stats/sport_stats.dart';
import 'package:insulink/src/sport/stats/sport_stats_charts.dart';

SetLog weighted(String ex, double kg, int reps) =>
    SetLog(exerciseId: ex, reps: reps, weightKg: kg, atEpochMs: 0);

WorkoutSession session(int startedAtMs, List<SetLog> sets) =>
    WorkoutSession(id: '$startedAtMs', routineId: 'r', startedAtMs: startedAtMs, sets: sets);

void main() {
  const bench = SportExercise(id: 'b', name: 'Bench', kind: ExerciseKind.weighted);
  const plank = SportExercise(id: 'p', name: 'Plank', kind: ExerciseKind.timed);

  test('rolls sets into per-exercise stats, newest session first', () {
    final stats = SportStats(
      [
        session(1000, [weighted('b', 60, 5), weighted('b', 80, 3)]),
        session(2000, [weighted('b', 100, 1)]),
      ],
      [bench],
    );
    final result = stats.build();

    expect(result, hasLength(1));
    final bench1rm = result.single;
    expect(bench1rm.totalSets, 3);
    // Best est. 1RM is the heavy triple at 80kg (80 * (1 + 3/30) = 88), which
    // beats the 100kg single (100 * (1 + 1/30) ≈ 103.3)... so the single wins.
    expect(bench1rm.best, closeTo(100 * (1 + 1 / 30), 0.001));
    // Two sessions, chronological.
    expect(bench1rm.sessions.map((s) => s.atMs), [1000, 2000]);
    expect(bench1rm.lastAtMs, 2000);
  });

  test('timed exercise scores on seconds; totals sum across sessions', () {
    final stats = SportStats(
      [
        session(1, [SetLog(exerciseId: 'p', seconds: 40, atEpochMs: 0)]),
        session(2, [SetLog(exerciseId: 'p', seconds: 65, atEpochMs: 0)]),
      ],
      [plank],
    );
    expect(stats.build().single.best, 65);
    expect(stats.totalSessions, 2);
  });

  test('sortStats orders by name without mutating the input', () {
    final stats = SportStats(
      [
        session(1, [weighted('b', 50, 5)]),
        session(2, [SetLog(exerciseId: 'p', seconds: 30, atEpochMs: 0)]),
      ],
      [bench, plank],
    ).build();
    final byName = sortStats(stats, StatSort.name);
    expect(byName.map((s) => s.exercise.name), ['Bench', 'Plank']);
    // Original list (last-sorted) is untouched.
    expect(stats.first.exercise.name, 'Plank');
  });

  test('weeklyWorkouts keeps 12 buckets and counts this week', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final buckets = weeklyWorkouts([session(now, [weighted('b', 50, 5)])]);
    expect(buckets, hasLength(12));
    expect(buckets.last.count, 1);
  });

  test('routineComparison only includes routines run twice, delta vs previous', () {
    final routines = [
      const SportRoutine(id: 'r', name: 'Push', items: []),
      const SportRoutine(id: 'x', name: 'Once', items: []),
    ];
    final sessions = [
      WorkoutSession(id: '1', routineId: 'r', startedAtMs: 1, sets: [weighted('b', 50, 5)]),
      WorkoutSession(id: '2', routineId: 'r', startedAtMs: 2, sets: [weighted('b', 60, 5)]),
      WorkoutSession(id: '3', routineId: 'x', startedAtMs: 3, sets: [weighted('b', 50, 5)]),
    ];
    final series = routineComparison(sessions, routines, 'Untitled');
    expect(series.map((s) => s.name), ['Push']);
    // Second run scores higher than the first → positive delta.
    expect(series.single.points.last.delta, greaterThan(0));
  });
}
