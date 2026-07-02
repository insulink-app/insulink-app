import 'cardio_models.dart';

/// Persisted state of an in-progress live training so it keeps recording in the
/// service isolate and resumes after the app is closed. The route itself lives
/// in the shared location log ([SportStore.appendLocationSample]); this only
/// tracks type, start and the paused span. All times are absolute epochs so the
/// elapsed duration recomputes correctly no matter how long the app was gone
/// (mirrors `WorkoutSnapshot`).
class ActiveTraining {
  final CardioType type;
  final int startMs;
  final int pausedTotalMs;

  /// When the current pause began (epoch ms), or null when running.
  final int? pausedAtMs;

  const ActiveTraining({
    required this.type,
    required this.startMs,
    this.pausedTotalMs = 0,
    this.pausedAtMs,
  });

  bool get isPaused => pausedAtMs != null;

  /// Reference "now", frozen at the pause moment while paused.
  int get _nowMs => pausedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  /// Wall-clock time since start, excluding paused spans.
  Duration get elapsed =>
      Duration(milliseconds: _nowMs - startMs - pausedTotalMs);

  ActiveTraining pause() => isPaused
      ? this
      : _copy(pausedAtMs: DateTime.now().millisecondsSinceEpoch);

  ActiveTraining resume() {
    final since = pausedAtMs;
    if (since == null) {
      return this;
    }
    final delta = DateTime.now().millisecondsSinceEpoch - since;
    return ActiveTraining(
      type: type,
      startMs: startMs,
      pausedTotalMs: pausedTotalMs + delta,
      pausedAtMs: null,
    );
  }

  ActiveTraining _copy({int? pausedAtMs}) => ActiveTraining(
    type: type,
    startMs: startMs,
    pausedTotalMs: pausedTotalMs,
    pausedAtMs: pausedAtMs,
  );

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'start': startMs,
    'paused': pausedTotalMs,
    'pausedAt': pausedAtMs,
  };

  factory ActiveTraining.fromJson(Map<String, dynamic> json) => ActiveTraining(
    type: CardioType.values.byName(json['type'] as String),
    startMs: json['start'] as int,
    pausedTotalMs: json['paused'] as int? ?? 0,
    pausedAtMs: json['pausedAt'] as int?,
  );
}
