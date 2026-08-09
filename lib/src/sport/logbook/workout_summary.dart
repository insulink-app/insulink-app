import 'package:insulink/src/sport/sport_models.dart';

/// The concrete figures of one completed workout, shown beneath the summary's
/// headline ring. Computed straight from a [WorkoutSession] with no exercise
/// lookup — the headline itself is [effortRatioVsPrevious].
class WorkoutSummary {
  WorkoutSummary(WorkoutSession session)
    : sets = session.sets.length,
      exercises = session.sets.map((set) => set.exerciseId).toSet().length,
      durationSecs = session.sets.isEmpty
          ? 0
          : (session.sets.last.atEpochMs - session.startedAtMs) ~/ 1000;

  final int sets;
  final int exercises;
  final int durationSecs;
}

/// How this session compares with [previous] as ONE ratio (1.0 = the same, 1.1 =
/// a tenth better), for the summary's headline ring.
///
/// Each exercise is measured against its own last time and the ratios are then
/// averaged, so every exercise counts the same. Dividing the two sessions'
/// TOTAL effort instead lets whichever exercise happens to carry the most reps
/// decide the number on its own: three more reps of a 100-rep exercise outweigh
/// doubling a heavy 5-rep one, and the figure stops saying anything about how
/// the session actually went.
///
/// Only exercises done in BOTH sessions count. A new one has nothing to compare
/// against, and one left out this time would read as -100 % and sink the whole
/// figure. Null when the two share none — there is nothing to say.
double? effortRatioVsPrevious(WorkoutSession current, WorkoutSession previous) {
  final before = _effortByExercise(previous);
  final ratios = <double>[];
  _effortByExercise(current).forEach((exerciseId, effort) {
    final base = before[exerciseId];
    if (base != null && base > 0) {
      ratios.add(effort / base);
    }
  });
  if (ratios.isEmpty) {
    return null;
  }
  return ratios.reduce((sum, ratio) => sum + ratio) / ratios.length;
}

/// Effort (reps + held seconds) per exercise of one session.
Map<String, int> _effortByExercise(WorkoutSession session) {
  final byExercise = <String, int>{};
  for (final set in session.sets) {
    byExercise[set.exerciseId] =
        (byExercise[set.exerciseId] ?? 0) + (set.reps ?? 0) + (set.seconds ?? 0);
  }
  return byExercise;
}
