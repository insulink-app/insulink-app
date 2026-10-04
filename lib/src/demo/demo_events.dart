/// The alarm history the analysis page lists, derived from the demo glucose
/// curve the way the real alarms are: one event each time the value crosses into
/// a worse zone, with the reading that crossed.
class DemoEvents {
  DemoEvents(this.readings);

  final Map<DateTime, int> readings;

  static const int urgentLow = 55;
  static const int low = 70;
  static const int high = 180;
  static const int urgentHigh = 250;

  /// The events as API history entries (`type`, `data`, `time`).
  late final List<Map<String, Object>> entries = _generate();

  List<Map<String, Object>> _generate() {
    final entries = <Map<String, Object>>[];
    var previousZone = 0;
    readings.forEach((time, value) {
      final zone = _zone(value);
      if (_worsens(previousZone, zone)) {
        entries.add({
          'type': _type(zone),
          'data': '$value',
          'time': time.millisecondsSinceEpoch,
        });
      }
      previousZone = zone;
    });
    return entries;
  }

  /// A new zone on the other side of the range, or a deeper one on the same.
  bool _worsens(int previousZone, int zone) {
    if (zone == 0) {
      return false;
    }
    return zone.sign != previousZone.sign || zone.abs() > previousZone.abs();
  }

  /// Negative for low, positive for high, 2 for urgent.
  int _zone(int value) {
    if (value < urgentLow) {
      return -2;
    }
    if (value < low) {
      return -1;
    }
    if (value > urgentHigh) {
      return 2;
    }
    return value > high ? 1 : 0;
  }

  String _type(int zone) => switch (zone) {
    -2 => 'glucose_low_urgent',
    -1 => 'glucose_low',
    2 => 'glucose_high_urgent',
    _ => 'glucose_high',
  };
}
