/// JSON-serialisable Sport-Domänenmodelle.
library;

/// Ein Gewichtseintrag: Zeitpunkt (epoch ms) + Gewicht in kg.
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

/// Was eine Übung pro Satz erfasst: Wiederholungen, Wiederholungen+Gewicht,
/// oder eine Dauer (z. B. Plank). Bestimmt die Eingaben im Editor und Runner.
enum ExerciseKind { reps, weighted, timed }

/// Eine benutzerdefinierte Übung in der Bibliothek.
class SportExercise {
  final String id;
  final String name;
  final ExerciseKind kind;

  const SportExercise({required this.id, required this.name, required this.kind});

  SportExercise copyWith({String? name, ExerciseKind? kind}) => SportExercise(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'kind': kind.name};

  factory SportExercise.fromJson(Map<String, dynamic> json) => SportExercise(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: ExerciseKind.values.byName(json['kind'] as String),
  );
}

/// Eine Übung innerhalb einer Routine mit ihren Zielwerten. [target] sind je
/// nach [ExerciseKind] der Übung Wiederholungen ODER Sekunden.
class RoutineItem {
  final String exerciseId;
  final int targetSets;
  final int target;
  final double targetWeight;
  final int restSeconds;

  const RoutineItem({
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
    exerciseId: exerciseId,
    targetSets: targetSets ?? this.targetSets,
    target: target ?? this.target,
    targetWeight: targetWeight ?? this.targetWeight,
    restSeconds: restSeconds ?? this.restSeconds,
  );

  Map<String, dynamic> toJson() => {
    'ex': exerciseId,
    'sets': targetSets,
    'target': target,
    'weight': targetWeight,
    'rest': restSeconds,
  };

  factory RoutineItem.fromJson(Map<String, dynamic> json) => RoutineItem(
    exerciseId: json['ex'] as String,
    targetSets: json['sets'] as int,
    target: json['target'] as int,
    targetWeight: (json['weight'] as num).toDouble(),
    restSeconds: json['rest'] as int,
  );
}

/// Eine Routine: ein Name und eine geordnete Abfolge von [RoutineItem]s.
class SportRoutine {
  final String id;
  final String name;
  final List<RoutineItem> items;

  const SportRoutine({required this.id, required this.name, required this.items});

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

/// Ein protokollierter Satz: Wiederholungen ODER Sekunden, optional Gewicht.
class SetLog {
  final String exerciseId;
  final int? reps;
  final int? seconds;
  final double? weightKg;
  final int atEpochMs;

  const SetLog({
    required this.exerciseId,
    this.reps,
    this.seconds,
    this.weightKg,
    required this.atEpochMs,
  });

  Map<String, dynamic> toJson() => {
    'ex': exerciseId,
    'reps': reps,
    'secs': seconds,
    'kg': weightKg,
    'ts': atEpochMs,
  };

  factory SetLog.fromJson(Map<String, dynamic> json) => SetLog(
    exerciseId: json['ex'] as String,
    reps: json['reps'] as int?,
    seconds: json['secs'] as int?,
    weightKg: (json['kg'] as num?)?.toDouble(),
    atEpochMs: json['ts'] as int,
  );
}

/// Eine durchgeführte Routine: Start + alle protokollierten Sätze. Basis der
/// Statistik in Phase 3.
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
