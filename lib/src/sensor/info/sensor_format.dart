// Shared value formatters for the sensor info pages (G7 SensorAttributes and
// Libre 3 Libre3Attributes) — kept in one place so the two builders format
// durations and timestamps identically.

/// A duration as `5 T 23 h` / `3 h 12 min` / `12 min`, or `—` when unknown.
/// [dayUnit] is the localized day abbreviation (`sensor.unit.day`).
String formatSensorDuration(int? secs, {String dayUnit = 'd'}) {
  if (secs == null) {
    return '—';
  }
  final days = secs ~/ 86400;
  final hours = (secs % 86400) ~/ 3600;
  final minutes = (secs % 3600) ~/ 60;
  if (days > 0) {
    return '$days $dayUnit $hours h';
  }
  if (hours > 0) {
    return '$hours h $minutes min';
  }
  return '$minutes min';
}

/// A `dd.MM., HH:mm` timestamp, or `—` when null.
String formatSensorDateTime(DateTime? time) {
  if (time == null) {
    return '—';
  }
  return '${twoDigits(time.day)}.${twoDigits(time.month)}., '
      '${twoDigits(time.hour)}:${twoDigits(time.minute)}';
}

String twoDigits(int value) => value.toString().padLeft(2, '0');
