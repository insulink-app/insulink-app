import 'dart:math';

import 'package:insulink/src/demo/demo_calendar.dart';

/// The daily measurements behind the Sport tab's "Today" boxes: steps, distance
/// and calories per day (today only up to now) and a weight every few days.
class DemoActivity {
  DemoActivity({required this.calendar, required this.random});

  final DemoCalendar calendar;
  final Random random;

  static const int days = 30;
  static const double kilometresPerStep = 0.00075;
  static const double caloriesPerStep = 0.045;

  /// The measurements as API entries (`type`, `value`, `time`).
  late final List<Map<String, Object>> entries = [
    for (final (index, day) in calendar.lastDays(days).indexed) ...[
      ..._activity(day),
      if (index % 3 == 0) _weight(day, index),
    ],
  ];

  List<Map<String, Object>> _activity(DateTime day) {
    final steps = (_stepsFor(day)).round();
    final noon = calendar.at(day, 12).millisecondsSinceEpoch;
    return [
      {'type': 'STEPS', 'value': steps, 'time': noon},
      {'type': 'DISTANCE', 'value': steps * kilometresPerStep, 'time': noon},
      {'type': 'CALORIES', 'value': steps * caloriesPerStep, 'time': noon},
    ];
  }

  /// A full day's steps, or the share of it walked so far today.
  double _stepsFor(DateTime day) {
    final fullDay = 5500 + random.nextDouble() * 6500;
    if (day != calendar.today) {
      return fullDay;
    }
    final hours = calendar.now.difference(day).inMinutes / 60;
    return fullDay * (hours / 22).clamp(0.05, 1);
  }

  Map<String, Object> _weight(DateTime day, int index) => {
    'type': 'WEIGHT',
    'value':
        ((76.2 - index * 0.02 + random.nextDouble() * 0.6) * 10).round() / 10,
    'time': calendar.at(day, 7.25).millisecondsSinceEpoch,
  };
}
