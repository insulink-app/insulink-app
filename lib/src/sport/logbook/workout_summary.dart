import 'package:insulink/src/sport/sport_models.dart';

/// The headline numbers of one completed workout. [effort] — total reps plus
/// held seconds across all sets — is the overall training value: a single
/// weight-free figure that is non-zero for any real session (reps for
/// rep/weighted exercises, seconds for timed ones), so it works for bodyweight
/// routines too and drives the "vs. last time" ring. [exercises], [sets] and
/// [durationSecs] are the concrete figures shown beneath it. Computed straight
/// from a [WorkoutSession] with no exercise lookup: reps/seconds already carry
/// the kind.
class WorkoutSummary {
  WorkoutSummary(WorkoutSession session)
    : sets = session.sets.length,
      exercises = session.sets.map((set) => set.exerciseId).toSet().length,
      effort = session.sets.fold(
        0,
        (sum, set) => sum + (set.reps ?? 0) + (set.seconds ?? 0),
      ),
      durationSecs = session.sets.isEmpty
          ? 0
          : (session.sets.last.atEpochMs - session.startedAtMs) ~/ 1000;

  final int sets;
  final int exercises;
  final int effort;
  final int durationSecs;
}
