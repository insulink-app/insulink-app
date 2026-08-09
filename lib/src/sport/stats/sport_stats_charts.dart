import 'package:insulink/src/sport/sport_models.dart';

/// One week's workout count in the frequency chart. [weekStartMs] is the local
/// Monday 00:00 of the week.
class WeeklyBucket {
  const WeeklyBucket({required this.weekStartMs, required this.count});

  final int weekStartMs;
  final int count;
}

/// One run of a routine on the comparison chart: its score and the change from
/// that routine's previous run.
class RoutinePoint {
  const RoutinePoint({
    required this.atMs,
    required this.value,
    required this.delta,
  });

  final int atMs;
  final double value;
  final double delta;
}

/// One routine's line on the comparison chart.
class RoutineSeries {
  const RoutineSeries({required this.name, required this.points});

  final String name;
  final List<RoutinePoint> points;
}

/// Local Monday 00:00 of [time]'s week.
DateTime _weekStart(DateTime time) {
  final day = DateTime(time.year, time.month, time.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// The last [weeks] weekly workout counts, empty weeks included so a training
/// gap actually shows as a gap. Weeks start Monday.
List<WeeklyBucket> weeklyWorkouts(
  List<WorkoutSession> sessions, {
  int weeks = 12,
}) {
  final currentWeek = _weekStart(DateTime.now());
  final counts = <int, int>{};
  for (var offset = weeks - 1; offset >= 0; offset -= 1) {
    counts[currentWeek.subtract(Duration(days: offset * 7)).millisecondsSinceEpoch] = 0;
  }
  for (final session in sessions) {
    final key = _weekStart(
      DateTime.fromMillisecondsSinceEpoch(session.startedAtMs),
    ).millisecondsSinceEpoch;
    if (counts.containsKey(key)) {
      counts[key] = counts[key]! + 1;
    }
  }
  final ordered = counts.keys.toList()..sort();
  return [
    for (final weekStart in ordered)
      WeeklyBucket(weekStartMs: weekStart, count: counts[weekStart]!),
  ];
}

/// A single "how much did I do this run" number, so two runs of the same routine
/// compare on one axis: reps, plus lifted volume (kg × reps) and held seconds.
///
/// ponytail: a flat sum mixes units; fine as a relative progress proxy, revisit
/// if a routine ever blends heavy lifting and long holds and the scale skews.
double workoutScore(WorkoutSession session) {
  return session.sets.fold(0.0, (sum, set) {
    final reps = set.reps ?? 0;
    return sum + reps + (set.weightKg ?? 0) * reps + (set.seconds ?? 0);
  });
}

/// One line per routine run at least twice, each point a run scored by
/// [workoutScore] with its change from the previous run. Free workouts have no
/// routine to name them, so they share [freeName] as one line.
List<RoutineSeries> routineComparison(
  List<WorkoutSession> sessions,
  List<SportRoutine> routines,
  String untitled,
  String freeName,
) {
  final nameById = {
    for (final routine in routines) routine.id: routine.name,
    freeRoutineId: freeName,
  };
  final runsByRoutine = <String, List<WorkoutSession>>{};
  for (final session in sessions) {
    (runsByRoutine[session.routineId] ??= []).add(session);
  }
  final series = <RoutineSeries>[];
  runsByRoutine.forEach((routineId, runs) {
    if (runs.length < 2) {
      return;
    }
    runs.sort((left, right) => left.startedAtMs.compareTo(right.startedAtMs));
    var previous = workoutScore(runs.first);
    final points = <RoutinePoint>[];
    for (final run in runs) {
      final value = workoutScore(run);
      points.add(
        RoutinePoint(atMs: run.startedAtMs, value: value, delta: value - previous),
      );
      previous = value;
    }
    series.add(RoutineSeries(name: nameById[routineId] ?? untitled, points: points));
  });
  return series;
}
