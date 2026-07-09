/// JSON-serialisable sport domain models.
library;

/// Counter for fallback ids of legacy [RoutineItem]s without a stored `id`
/// (migration).
int _legacyItemId = 0;

/// A weight entry: timestamp (epoch ms) + weight in kg.
class WeightEntry {
  final int atEpochMs;
  final double kg;

  const WeightEntry({required this.atEpochMs, required this.kg});

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(atEpochMs);

  Map<String, dynamic> toJson() => {'ts': atEpochMs, 'kg': kg};

  factory WeightEntry.fromJson(Map<String, dynamic> json) => WeightEntry(
    atEpochMs: json['ts'] as int,
    kg: (json['kg'] as num).toDouble(),
  );
}

/// Daily activity from Google Health: steps, distance (km) and active calories
/// of a calendar day. [dateKey] is `yyyy-mm-dd` (local). Persisted as a
/// long-term archive that feeds the detail pages (steps/distance/calories).
class DailyActivity {
  final String dateKey;
  final int steps;
  final double distanceKm;
  final double calories;

  const DailyActivity({
    required this.dateKey,
    required this.steps,
    required this.distanceKm,
    required this.calories,
  });

  DateTime get date => DateTime.parse(dateKey);

  Map<String, dynamic> toJson() => {
    'd': dateKey,
    'steps': steps,
    'km': distanceKm,
    'kcal': calories,
  };

  factory DailyActivity.fromJson(Map<String, dynamic> json) => DailyActivity(
    dateKey: json['d'] as String,
    steps: json['steps'] as int,
    distanceKm: (json['km'] as num).toDouble(),
    calories: (json['kcal'] as num).toDouble(),
  );
}

/// Which daily metric an activity detail page shows.
enum ActivityMetric { steps, distance, calories }

/// What an exercise records per set: reps, reps+weight, or a duration (e.g.
/// plank). Determines the inputs in the editor and runner.
enum ExerciseKind { reps, weighted, timed }

/// A user-defined exercise in the library.
class SportExercise {
  final String id;
  final String name;
  final ExerciseKind kind;

  const SportExercise({
    required this.id,
    required this.name,
    required this.kind,
  });

  SportExercise copyWith({String? name, ExerciseKind? kind}) =>
      SportExercise(id: id, name: name ?? this.name, kind: kind ?? this.kind);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'kind': kind.name};

  factory SportExercise.fromJson(Map<String, dynamic> json) => SportExercise(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: ExerciseKind.values.byName(json['kind'] as String),
  );
}

/// An exercise inside a routine with its target values. Depending on the
/// exercise's [ExerciseKind], [target] is reps OR seconds. [id] is stable across
/// reorders (reorder key) and identifies the entry, not the referenced exercise
/// (the same exercise may appear multiple times).
class RoutineItem {
  final String id;
  final String exerciseId;
  final int targetSets;
  final int target;
  final double targetWeight;
  final int restSeconds;

  const RoutineItem({
    required this.id,
    required this.exerciseId,
    this.targetSets = 3,
    this.target = 10,
    this.targetWeight = 0,
    this.restSeconds = 60,
  });

  RoutineItem copyWith({
    int? targetSets,
    int? target,
    double? targetWeight,
    int? restSeconds,
  }) => RoutineItem(
    id: id,
    exerciseId: exerciseId,
    targetSets: targetSets ?? this.targetSets,
    target: target ?? this.target,
    targetWeight: targetWeight ?? this.targetWeight,
    restSeconds: restSeconds ?? this.restSeconds,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'ex': exerciseId,
    'sets': targetSets,
    'target': target,
    'weight': targetWeight,
    'rest': restSeconds,
  };

  /// Legacy entries without an `id` get one on load — it's written on the next
  /// save (migration).
  factory RoutineItem.fromJson(Map<String, dynamic> json) => RoutineItem(
    id: json['id'] as String? ?? 'legacy-${_legacyItemId++}',
    exerciseId: json['ex'] as String,
    targetSets: json['sets'] as int,
    target: json['target'] as int,
    targetWeight: (json['weight'] as num).toDouble(),
    restSeconds: json['rest'] as int,
  );
}

/// A routine: a name and an ordered sequence of [RoutineItem]s.
class SportRoutine {
  final String id;
  final String name;
  final List<RoutineItem> items;

  const SportRoutine({
    required this.id,
    required this.name,
    required this.items,
  });

  SportRoutine copyWith({String? name, List<RoutineItem>? items}) =>
      SportRoutine(id: id, name: name ?? this.name, items: items ?? this.items);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory SportRoutine.fromJson(Map<String, dynamic> json) => SportRoutine(
    id: json['id'] as String,
    name: json['name'] as String,
    items: (json['items'] as List)
        .cast<Map<String, dynamic>>()
        .map(RoutineItem.fromJson)
        .toList(),
  );
}

/// A logged set: reps OR seconds, optionally weight. [durationSecs] is the wall
/// time actually spent performing the set (pauses excluded); [restSecs] is the
/// rest actually taken AFTER it before the next set (null for the last set of a
/// workout and for manually added sets). Both are null on legacy logs.
class SetLog {
  final String exerciseId;
  final int? reps;
  final int? seconds;
  final double? weightKg;
  final int? durationSecs;
  final int? restSecs;
  final int atEpochMs;

  const SetLog({
    required this.exerciseId,
    this.reps,
    this.seconds,
    this.weightKg,
    this.durationSecs,
    this.restSecs,
    required this.atEpochMs,
  });

  SetLog copyWith({
    int? reps,
    int? seconds,
    double? weightKg,
    int? durationSecs,
    int? restSecs,
  }) => SetLog(
    exerciseId: exerciseId,
    reps: reps ?? this.reps,
    seconds: seconds ?? this.seconds,
    weightKg: weightKg ?? this.weightKg,
    durationSecs: durationSecs ?? this.durationSecs,
    restSecs: restSecs ?? this.restSecs,
    atEpochMs: atEpochMs,
  );

  Map<String, dynamic> toJson() => {
    'ex': exerciseId,
    'reps': reps,
    'secs': seconds,
    'kg': weightKg,
    'dur': durationSecs,
    'rest': restSecs,
    'ts': atEpochMs,
  };

  factory SetLog.fromJson(Map<String, dynamic> json) => SetLog(
    exerciseId: json['ex'] as String,
    reps: json['reps'] as int?,
    seconds: json['secs'] as int?,
    weightKg: (json['kg'] as num?)?.toDouble(),
    durationSecs: json['dur'] as int?,
    restSecs: json['rest'] as int?,
    atEpochMs: json['ts'] as int,
  );
}

/// A completed routine: start + all logged sets. Basis for the statistics in
/// phase 3.
class WorkoutSession {
  final String id;
  final String routineId;
  final int startedAtMs;
  final List<SetLog> sets;

  const WorkoutSession({
    required this.id,
    required this.routineId,
    required this.startedAtMs,
    required this.sets,
  });

  WorkoutSession copyWith({List<SetLog>? sets}) => WorkoutSession(
    id: id,
    routineId: routineId,
    startedAtMs: startedAtMs,
    sets: sets ?? this.sets,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'routine': routineId,
    'started': startedAtMs,
    'sets': sets.map((set) => set.toJson()).toList(),
  };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
    id: json['id'] as String,
    routineId: json['routine'] as String,
    startedAtMs: json['started'] as int,
    sets: (json['sets'] as List)
        .cast<Map<String, dynamic>>()
        .map(SetLog.fromJson)
        .toList(),
  );
}
