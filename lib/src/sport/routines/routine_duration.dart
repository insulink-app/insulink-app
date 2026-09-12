import '../sport_models.dart';

/// Estimated duration of a routine in whole seconds. Once the routine has been
/// logged at least once, the estimate is the AVERAGE actual duration of its past
/// sessions (far more reliable than any model). Only when it has never been run
/// do we fall back to the additive guess: each set costs ~1 min of work (or its
/// target seconds for a timed exercise) plus its rest.
int estimatedRoutineSeconds(
  SportRoutine routine,
  List<SportExercise> exercises,
  List<WorkoutSession> sessions,
) {
  final measured = _averagePastSeconds(routine.id, sessions);
  if (measured != null) {
    return measured;
  }
  return plannedRoutineSeconds(routine, exercises);
}

/// Average duration (seconds) of the most recent completed sessions of this
/// routine, or null if it has never been run with logged sets. Limited to the
/// last few sessions so a changed routine converges on its current length.
int? _averagePastSeconds(String routineId, List<WorkoutSession> sessions) {
  final durations = <int>[];
  for (final session in sessions.reversed) {
    if (session.routineId == routineId && session.sets.isNotEmpty) {
      durations.add(session.sets.last.atEpochMs - session.startedAtMs);
      if (durations.length >= 5) {
        break;
      }
    }
  }
  if (durations.isEmpty) {
    return null;
  }
  final total = durations.reduce((sum, value) => sum + value);
  return (total / durations.length / 1000).round();
}

/// The additive guess on its own: what the routine plans for, ignoring how long
/// it actually took before. Each set costs ~1 min of work (or its target seconds
/// for a timed exercise) plus its rest. Used where no past session applies — a
/// routine never run, and the running workout's prediction before its first set
/// gives a pace to extrapolate.
int plannedRoutineSeconds(SportRoutine routine, List<SportExercise> exercises) {
  var seconds = 0;
  for (final item in routine.items) {
    final exercise = _exerciseById(exercises, item.exerciseId);
    final perSet = exercise?.kind == ExerciseKind.timed ? item.target : 60;
    seconds += item.targetSets * (perSet + item.restSeconds);
  }
  return seconds;
}

SportExercise? _exerciseById(List<SportExercise> exercises, String id) {
  for (final exercise in exercises) {
    if (exercise.id == id) {
      return exercise;
    }
  }
  return null;
}
