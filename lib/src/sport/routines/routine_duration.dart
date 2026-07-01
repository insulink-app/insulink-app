import '../sport_models.dart';

/// Rough estimated duration of a routine in whole minutes: each set costs ~1 min
/// of work (or its target seconds for a timed exercise) plus its rest. Feeds the
/// "ca. X min" hint on the routine card and editor. `ponytail:` a flat 60 s per
/// set is close enough for planning; wire in real per-exercise averages only if
/// the estimate proves misleading.
int estimatedRoutineMinutes(
  SportRoutine routine,
  List<SportExercise> exercises,
) {
  var seconds = 0;
  for (final item in routine.items) {
    final exercise = _exerciseById(exercises, item.exerciseId);
    final perSet = exercise?.kind == ExerciseKind.timed ? item.target : 60;
    seconds += item.targetSets * (perSet + item.restSeconds);
  }
  return (seconds / 60).round();
}

SportExercise? _exerciseById(List<SportExercise> exercises, String id) {
  for (final exercise in exercises) {
    if (exercise.id == id) {
      return exercise;
    }
  }
  return null;
}
