/// JSON-serialisable Google Health domain model.
library;

/// One calendar day of Google Health health data read from Health Connect. [dateKey] is
/// `yyyy-mm-dd` (local). All metrics are nullable because a given day may only
/// carry some of them (e.g. resting HR but no sleep session yet).
class GoogleHealthDay {
  final String dateKey;
  final int? restingHr;
  final int? sleepMinutes;
  final int? spo2;
  final int? respiratoryRate;
  final SleepStages? sleepStages;

  /// Chronological stage segments of the night (the hypnogram) — only the most
  /// recent night carries it (older nights keep just the [sleepStages] totals),
  /// so the archive holds one night of segments, not thirty.
  final List<SleepSegment>? sleepTimeline;

  const GoogleHealthDay({
    required this.dateKey,
    this.restingHr,
    this.sleepMinutes,
    this.spo2,
    this.respiratoryRate,
    this.sleepStages,
    this.sleepTimeline,
  });

  Map<String, dynamic> toJson() => {
    'd': dateKey,
    if (restingHr != null) 'rhr': restingHr,
    if (sleepMinutes != null) 'sleep': sleepMinutes,
    if (spo2 != null) 'spo2': spo2,
    if (respiratoryRate != null) 'rr': respiratoryRate,
    if (sleepStages != null) 'stages': sleepStages!.toJson(),
    if (sleepTimeline != null)
      'tl': [for (final s in sleepTimeline!) s.toJson()],
  };

  factory GoogleHealthDay.fromJson(Map<String, dynamic> json) => GoogleHealthDay(
    dateKey: json['d'] as String,
    restingHr: json['rhr'] as int?,
    sleepMinutes: json['sleep'] as int?,
    spo2: json['spo2'] as int?,
    respiratoryRate: json['rr'] as int?,
    sleepStages: json['stages'] == null
        ? null
        : SleepStages.fromJson(json['stages'] as Map<String, dynamic>),
    sleepTimeline: json['tl'] == null
        ? null
        : [
            for (final s in json['tl'] as List)
              SleepSegment.fromJson(s as Map<String, dynamic>),
          ],
  );

  DateTime get date => DateTime.parse(dateKey);

  int? value(GoogleHealthMetric metric) => switch (metric) {
    GoogleHealthMetric.restingHr => restingHr,
    GoogleHealthMetric.sleep => sleepMinutes,
    GoogleHealthMetric.spo2 => spo2,
    GoogleHealthMetric.respiratoryRate => respiratoryRate,
  };
}

/// Which daily Google Health metric a detail page shows (the archive-backed tiles).
enum GoogleHealthMetric { restingHr, sleep, spo2, respiratoryRate }

/// The four sleep stages of one night, in minutes, summed from Health Connect's
/// per-stage records (SLEEP_DEEP/REM/LIGHT/AWAKE).
class SleepStages {
  final int deep;
  final int rem;
  final int light;
  final int awake;

  const SleepStages({
    this.deep = 0,
    this.rem = 0,
    this.light = 0,
    this.awake = 0,
  });

  int get total => deep + rem + light + awake;
  bool get isEmpty => total == 0;

  Map<String, dynamic> toJson() => {
    'deep': deep,
    'rem': rem,
    'light': light,
    'awake': awake,
  };

  factory SleepStages.fromJson(Map<String, dynamic> json) => SleepStages(
    deep: json['deep'] as int? ?? 0,
    rem: json['rem'] as int? ?? 0,
    light: json['light'] as int? ?? 0,
    awake: json['awake'] as int? ?? 0,
  );
}

/// Which sleep stage a segment is, in Health Connect's stage-record order — the
/// index also indexes the [SleepStages] fields and the hypnogram lanes.
enum SleepStage { deep, rem, light, awake }

/// One chronological stretch of a single sleep [stage], `[startMs, endMs)` epoch
/// ms — the raw material for the hypnogram (when each phase began/ended).
class SleepSegment {
  final SleepStage stage;
  final int startMs;
  final int endMs;

  const SleepSegment({
    required this.stage,
    required this.startMs,
    required this.endMs,
  });

  Map<String, dynamic> toJson() => {
    's': stage.index,
    'a': startMs,
    'b': endMs,
  };

  factory SleepSegment.fromJson(Map<String, dynamic> json) => SleepSegment(
    stage: SleepStage.values[json['s'] as int],
    startMs: json['a'] as int,
    endMs: json['b'] as int,
  );
}

/// Formats sleep minutes as `Xh Ym` (e.g. 440 → "7h 20m"), or "–" when unknown.
String formatSleepMinutes(int? minutes) {
  if (minutes == null) {
    return '–';
  }
  return '${minutes ~/ 60}h ${minutes % 60}m';
}
