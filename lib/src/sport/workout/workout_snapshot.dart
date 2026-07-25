import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';

/// Persisted state of an in-progress workout so it resumes exactly after the app
/// is closed. All times are absolute epochs, so elapsed/rest recompute correctly
/// no matter how long the app was gone.
class WorkoutSnapshot {
  final String routineId;
  final String routineName;

  /// The driving device's own copy of the routine's ordered items, carried in
  /// the snapshot so a follower renders the exercise/set/target the DRIVER is on
  /// — resolving [exerciseIndex]/[setIndex] against the follower's local routine
  /// breaks the moment the two copies differ (a reorder, an edit, a stale pull),
  /// showing the wrong exercise/set/time. Empty only for a legacy snapshot from
  /// before this field; callers then fall back to the local routine.
  final List<RoutineItem> items;

  final int startedAtMs;
  final int exerciseIndex;
  final int setIndex;
  final WorkoutPhase phase;
  final int setStartedAtMs;
  final int? restEndsAtMs;
  final int? restStartedAtMs;
  final int pausedTotalMs;

  /// When the workout was paused, or null while it runs. Carried like every
  /// other time as an absolute epoch, so a follower freezes its clocks at the
  /// same instant instead of counting on while the other screen sits paused.
  final int? pausedAtMs;
  final int currentReps;
  final double currentWeight;
  final List<SetLog> sets;

  const WorkoutSnapshot({
    required this.routineId,
    this.routineName = '',
    this.items = const [],
    required this.startedAtMs,
    required this.exerciseIndex,
    required this.setIndex,
    required this.phase,
    required this.setStartedAtMs,
    required this.restEndsAtMs,
    required this.restStartedAtMs,
    required this.pausedTotalMs,
    this.pausedAtMs,
    required this.currentReps,
    required this.currentWeight,
    required this.sets,
  });

  Map<String, dynamic> toJson() => {
    'routine': routineId,
    'name': routineName,
    'items': items.map((item) => item.toJson()).toList(),
    'started': startedAtMs,
    'ex': exerciseIndex,
    'set': setIndex,
    'phase': phase.name,
    'setStarted': setStartedAtMs,
    'restEnds': restEndsAtMs,
    'restStarted': restStartedAtMs,
    'paused': pausedTotalMs,
    'pausedAt': pausedAtMs,
    'reps': currentReps,
    'weight': currentWeight,
    'sets': sets.map((set) => set.toJson()).toList(),
  };

  factory WorkoutSnapshot.fromJson(Map<String, dynamic> json) =>
      WorkoutSnapshot(
        routineId: json['routine'] as String,
        routineName: json['name'] as String? ?? '',
        items: (json['items'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(RoutineItem.fromJson)
                .toList() ??
            const [],
        startedAtMs: json['started'] as int,
        exerciseIndex: json['ex'] as int,
        setIndex: json['set'] as int,
        phase: WorkoutPhase.values.byName(json['phase'] as String),
        setStartedAtMs: json['setStarted'] as int,
        restEndsAtMs: json['restEnds'] as int?,
        restStartedAtMs: json['restStarted'] as int?,
        pausedTotalMs: json['paused'] as int,
        pausedAtMs: json['pausedAt'] as int?,
        currentReps: json['reps'] as int,
        currentWeight: (json['weight'] as num).toDouble(),
        sets: (json['sets'] as List)
            .cast<Map<String, dynamic>>()
            .map(SetLog.fromJson)
            .toList(),
      );
}
