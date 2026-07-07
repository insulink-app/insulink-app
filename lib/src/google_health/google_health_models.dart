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
  final SleepStages? sleepStages;

  const GoogleHealthDay({
    required this.dateKey,
    this.restingHr,
    this.sleepMinutes,
    this.spo2,
    this.sleepStages,
  });

  Map<String, dynamic> toJson() => {
    'd': dateKey,
    if (restingHr != null) 'rhr': restingHr,
    if (sleepMinutes != null) 'sleep': sleepMinutes,
    if (spo2 != null) 'spo2': spo2,
    if (sleepStages != null) 'stages': sleepStages!.toJson(),
  };

  factory GoogleHealthDay.fromJson(Map<String, dynamic> json) => GoogleHealthDay(
    dateKey: json['d'] as String,
    restingHr: json['rhr'] as int?,
    sleepMinutes: json['sleep'] as int?,
    spo2: json['spo2'] as int?,
    sleepStages: json['stages'] == null
        ? null
        : SleepStages.fromJson(json['stages'] as Map<String, dynamic>),
  );

  DateTime get date => DateTime.parse(dateKey);

  int? value(GoogleHealthMetric metric) => switch (metric) {
    GoogleHealthMetric.restingHr => restingHr,
    GoogleHealthMetric.sleep => sleepMinutes,
    GoogleHealthMetric.spo2 => spo2,
  };
}

/// Which daily Google Health metric a detail page shows (the archive-backed tiles).
enum GoogleHealthMetric { restingHr, sleep, spo2 }

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

/// Formats sleep minutes as `Xh Ym` (e.g. 440 → "7h 20m"), or "–" when unknown.
String formatSleepMinutes(int? minutes) {
  if (minutes == null) {
    return '–';
  }
  return '${minutes ~/ 60}h ${minutes % 60}m';
}
