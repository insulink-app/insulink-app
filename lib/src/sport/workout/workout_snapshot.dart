import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';

/// Persisted state of an in-progress workout so it resumes exactly after the app
/// is closed. All times are absolute epochs, so elapsed/rest recompute correctly
/// no matter how long the app was gone.
class WorkoutSnapshot {
  final String routineId;
  final int startedAtMs;
  final int exerciseIndex;
  final int setIndex;
  final WorkoutPhase phase;
  final int setStartedAtMs;
  final int? restEndsAtMs;
  final int pausedTotalMs;
  final int currentReps;
  final double currentWeight;
  final List<SetLog> sets;

  const WorkoutSnapshot({
    required this.routineId,
    required this.startedAtMs,
    required this.exerciseIndex,
    required this.setIndex,
    required this.phase,
    required this.setStartedAtMs,
    required this.restEndsAtMs,
    required this.pausedTotalMs,
    required this.currentReps,
    required this.currentWeight,
    required this.sets,
  });

  Map<String, dynamic> toJson() => {
    'routine': routineId,
    'started': startedAtMs,
    'ex': exerciseIndex,
    'set': setIndex,
    'phase': phase.name,
    'setStarted': setStartedAtMs,
    'restEnds': restEndsAtMs,
    'paused': pausedTotalMs,
    'reps': currentReps,
    'weight': currentWeight,
    'sets': sets.map((set) => set.toJson()).toList(),
  };

  factory WorkoutSnapshot.fromJson(Map<String, dynamic> json) => WorkoutSnapshot(
    routineId: json['routine'] as String,
    startedAtMs: json['started'] as int,
    exerciseIndex: json['ex'] as int,
    setIndex: json['set'] as int,
    phase: WorkoutPhase.values.byName(json['phase'] as String),
    setStartedAtMs: json['setStarted'] as int,
    restEndsAtMs: json['restEnds'] as int?,
    pausedTotalMs: json['paused'] as int,
    currentReps: json['reps'] as int,
    currentWeight: (json['weight'] as num).toDouble(),
    sets: (json['sets'] as List)
        .cast<Map<String, dynamic>>()
        .map(SetLog.fromJson)
        .toList(),
  );
}
