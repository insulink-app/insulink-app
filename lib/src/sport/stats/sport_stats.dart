import 'package:insulink/src/sport/sport_models.dart';

/// One session's contribution to an exercise's history: when, the best set score
/// that session, and how many sets were logged.
class ExerciseSession {
  const ExerciseSession({
    required this.atMs,
    required this.best,
    required this.sets,
  });

  final int atMs;
  final double best;
  final int sets;
}

/// Rolled-up statistics for a single exercise across every logged workout.
class ExerciseStat {
  ExerciseStat({
    required this.exercise,
    required this.totalSets,
    required this.best,
    required this.lastAtMs,
    required this.sessions,
  });

  final SportExercise exercise;
  final int totalSets;
  final double best;
  final int lastAtMs;

  /// Chronological — the basis for the progression chart.
  final List<ExerciseSession> sessions;
}

enum StatSort { last, name, sets, best }

/// Turns the logged workouts into per-exercise statistics — a Dart port of the
/// web panel's exercise-stats page. The one per-set "score" is est. 1RM for
/// weighted exercises, seconds for timed, reps otherwise, so a heavy triple and
/// a light set of twelve compare on one axis.
class SportStats {
  SportStats(this.sessions, this.exercises);

  final List<WorkoutSession> sessions;
  final List<SportExercise> exercises;

  int get totalSessions => sessions.length;

  int get totalSets =>
      sessions.fold(0, (sum, session) => sum + session.sets.length);

  int get totalReps => sessions.fold(
    0,
    (sum, session) =>
        sum + session.sets.fold(0, (inner, set) => inner + (set.reps ?? 0)),
  );

  /// Total time actually spent performing sets, in minutes (rest excluded).
  /// Legacy sets without a recorded duration count as 0, so the number only
  /// grows once workouts are run through the timed runner.
  int get totalTrainingMinutes =>
      sessions.fold(
        0,
        (sum, session) =>
            sum +
            session.sets.fold(
              0,
              (inner, set) => inner + (set.durationSecs ?? 0),
            ),
      ) ~/
      60;

  /// Epley one-rep-max estimate for a weighted set; 0 without both weight and
  /// reps, so the standard formula lets weighted sets rank on est. 1RM.
  static double _oneRepMax(SetLog set) {
    final kg = set.weightKg ?? 0;
    final reps = set.reps ?? 0;
    if (kg <= 0 || reps <= 0) {
      return 0;
    }
    return kg * (1 + reps / 30);
  }

  /// The set's score in its exercise kind's own unit.
  static double score(SetLog set, ExerciseKind kind) {
    switch (kind) {
      case ExerciseKind.weighted:
        return _oneRepMax(set);
      case ExerciseKind.timed:
        return (set.seconds ?? 0).toDouble();
      case ExerciseKind.reps:
        return (set.reps ?? 0).toDouble();
    }
  }

  /// Per-exercise stats, most-recently-trained first.
  List<ExerciseStat> build() {
    final byId = {for (final exercise in exercises) exercise.id: exercise};
    final rolling = <String, _Rolling>{};
    for (final session in sessions) {
      _foldSession(session, byId, rolling);
    }
    final stats = [for (final entry in rolling.values) entry.finish()];
    stats.sort((left, right) => right.lastAtMs.compareTo(left.lastAtMs));
    return stats;
  }

  void _foldSession(
    WorkoutSession session,
    Map<String, SportExercise> byId,
    Map<String, _Rolling> rolling,
  ) {
    final perExercise = <String, ({double best, int count})>{};
    for (final set in session.sets) {
      final exercise = byId[set.exerciseId];
      if (exercise == null) {
        continue;
      }
      final value = score(set, exercise.kind);
      final running = perExercise[set.exerciseId] ?? (best: 0.0, count: 0);
      perExercise[set.exerciseId] = (
        best: value > running.best ? value : running.best,
        count: running.count + 1,
      );
    }
    perExercise.forEach((exerciseId, roll) {
      (rolling[exerciseId] ??= _Rolling(
        byId[exerciseId]!,
      )).add(session.startedAtMs, roll.best, roll.count);
    });
  }
}

/// Sorts a copy of [stats] by [sort] (never mutates the input).
List<ExerciseStat> sortStats(List<ExerciseStat> stats, StatSort sort) {
  final sorted = [...stats];
  switch (sort) {
    case StatSort.name:
      sorted.sort(
        (left, right) => left.exercise.name.toLowerCase().compareTo(
          right.exercise.name.toLowerCase(),
        ),
      );
    case StatSort.sets:
      sorted.sort((left, right) => right.totalSets.compareTo(left.totalSets));
    case StatSort.best:
      sorted.sort((left, right) => right.best.compareTo(left.best));
    case StatSort.last:
      sorted.sort((left, right) => right.lastAtMs.compareTo(left.lastAtMs));
  }
  return sorted;
}

/// Accumulator for one exercise while [SportStats.build] folds the sessions.
class _Rolling {
  _Rolling(this.exercise);

  final SportExercise exercise;
  int totalSets = 0;
  double best = 0;
  int lastAtMs = 0;
  final List<ExerciseSession> sessions = [];

  void add(int atMs, double sessionBest, int count) {
    totalSets += count;
    best = sessionBest > best ? sessionBest : best;
    lastAtMs = atMs > lastAtMs ? atMs : lastAtMs;
    sessions.add(ExerciseSession(atMs: atMs, best: sessionBest, sets: count));
  }

  ExerciseStat finish() {
    sessions.sort((left, right) => left.atMs.compareTo(right.atMs));
    return ExerciseStat(
      exercise: exercise,
      totalSets: totalSets,
      best: best,
      lastAtMs: lastAtMs,
      sessions: sessions,
    );
  }
}
