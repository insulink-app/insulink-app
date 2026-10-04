import 'dart:math';

import 'package:insulink/src/demo/demo_calendar.dart';
import 'package:insulink/src/demo/demo_sleep.dart';

/// A training window the heart-rate curve rises in.
typedef DemoEffort = ({DateTime start, DateTime end, int heartRate});

/// The demo's health record: a night of sleep and a resting heart rate per day,
/// a heart-rate curve over the last days that follows sleep and the trainings,
/// and a few lab HbA1c values.
class DemoHealth {
  DemoHealth({
    required this.calendar,
    required this.random,
    required this.efforts,
  });

  final DemoCalendar calendar;
  final Random random;
  final List<DemoEffort> efforts;

  static const int recordedDays = 30;
  static const int pulseDays = 10;
  static const Duration pulseStep = Duration(minutes: 5);

  late final List<DemoSleepNight> _nights = [
    for (final day in calendar.lastDays(recordedDays))
      DemoSleepNight(wakeDay: day, random: random),
  ];

  /// One API health day per night that has already ended.
  late final List<Map<String, Object>> healthDays = [
    for (final night in _nights)
      if (calendar.isPast(night.wake))
        night.toDay(calendar, 56 + random.nextInt(6)),
  ];

  /// Heart-rate samples (`t` epoch ms, `b` bpm) every five minutes.
  late final List<Map<String, int>> pulse = _pulse();

  List<Map<String, int>> _pulse() {
    final samples = <Map<String, int>>[];
    var time = calendar.today.subtract(const Duration(days: pulseDays));
    for (; calendar.isPast(time); time = time.add(pulseStep)) {
      samples.add({'t': time.millisecondsSinceEpoch, 'b': _bpmAt(time)});
    }
    return samples;
  }

  int _bpmAt(DateTime time) {
    final noise = random.nextInt(7) - 3;
    for (final effort in efforts) {
      if (!time.isBefore(effort.start) && time.isBefore(effort.end)) {
        return effort.heartRate + noise * 2;
      }
    }
    return (_asleep(time) ? 53 : 68 + 6 * sin(time.hour / 24 * 2 * pi))
            .round() +
        noise;
  }

  bool _asleep(DateTime time) => _nights.any(
    (night) => !time.isBefore(night.bedtime) && time.isBefore(night.wake),
  );

  /// Lab HbA1c readings (`time` epoch ms, `percent`).
  late final List<Map<String, Object>> hba1c = [
    for (final (daysAgo, percent) in [
      (270, 6.6),
      (180, 6.3),
      (90, 6.0),
      (12, 5.8),
    ])
      {
        'time': calendar.today
            .subtract(Duration(days: daysAgo))
            .add(const Duration(hours: 9))
            .millisecondsSinceEpoch,
        'percent': percent,
      },
  ];
}
