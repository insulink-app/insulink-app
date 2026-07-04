/// JSON-serialisable Fitbit domain model.
library;

/// One calendar day of Fitbit health data read from Health Connect. [dateKey] is
/// `yyyy-mm-dd` (local). All metrics are nullable because a given day may only
/// carry some of them (e.g. resting HR but no sleep session yet).
class FitbitDay {
  final String dateKey;
  final int? restingHr;
  final int? sleepMinutes;
  final int? spo2;

  const FitbitDay({
    required this.dateKey,
    this.restingHr,
    this.sleepMinutes,
    this.spo2,
  });

  Map<String, dynamic> toJson() => {
    'd': dateKey,
    if (restingHr != null) 'rhr': restingHr,
    if (sleepMinutes != null) 'sleep': sleepMinutes,
    if (spo2 != null) 'spo2': spo2,
  };

  factory FitbitDay.fromJson(Map<String, dynamic> json) => FitbitDay(
    dateKey: json['d'] as String,
    restingHr: json['rhr'] as int?,
    sleepMinutes: json['sleep'] as int?,
    spo2: json['spo2'] as int?,
  );
}

/// Formats sleep minutes as `Xh Ym` (e.g. 440 → "7h 20m"), or "–" when unknown.
String formatSleepMinutes(int? minutes) {
  if (minutes == null) {
    return '–';
  }
  return '${minutes ~/ 60}h ${minutes % 60}m';
}
