import 'dart:math';

import 'package:insulink/src/demo/demo_calendar.dart';

/// One night of demo sleep: 90-minute cycles whose deep share shrinks and REM
/// share grows towards morning, the way a real hypnogram looks.
class DemoSleepNight {
  DemoSleepNight({required this.wakeDay, required this.random});

  final DateTime wakeDay;
  final Random random;

  static const int deep = 0;
  static const int rem = 1;
  static const int light = 2;
  static const int awake = 3;

  late final DateTime bedtime = wakeDay.subtract(
    Duration(minutes: 30 + random.nextInt(50)),
  );

  late final DateTime wake = wakeDay.add(
    Duration(minutes: 6 * 60 + 40 + random.nextInt(50)),
  );

  /// The segments as API timeline entries (`s` stage index, `a`/`b` epoch ms).
  late final List<Map<String, int>> timeline = _timeline();

  List<Map<String, int>> _timeline() {
    final segments = <Map<String, int>>[];
    var clock = bedtime;
    for (var cycle = 0; clock.isBefore(wake); cycle++) {
      for (final (stage, minutes) in _cycle(cycle)) {
        final end = _earlier(clock.add(Duration(minutes: minutes)), wake);
        segments.add({
          's': stage,
          'a': clock.millisecondsSinceEpoch,
          'b': end.millisecondsSinceEpoch,
        });
        clock = end;
      }
    }
    return segments;
  }

  List<(int, int)> _cycle(int cycle) => [
    (light, 20 + random.nextInt(10)),
    (deep, max(6, 32 - cycle * 7)),
    (light, 15 + random.nextInt(10)),
    (rem, 12 + cycle * 6),
    if (random.nextDouble() < 0.4) (awake, 3 + random.nextInt(6)),
  ];

  DateTime _earlier(DateTime first, DateTime second) =>
      first.isBefore(second) ? first : second;

  /// Minutes spent in each stage, summed over the timeline.
  int minutesIn(int stage) => timeline
      .where((segment) => segment['s'] == stage)
      .fold(
        0,
        (sum, segment) => sum + (segment['b']! - segment['a']!) ~/ 60000,
      );

  /// The night as an API health day (`d`, `rhr`, `sleep`, `rr`, `stages`, `tl`).
  Map<String, Object> toDay(DemoCalendar calendar, int restingHeartRate) => {
    'd': calendar.dateKey(wakeDay),
    'rhr': restingHeartRate,
    'sleep': wake.difference(bedtime).inMinutes - minutesIn(awake),
    'rr': 13 + random.nextInt(3),
    'stages': {
      'deep': minutesIn(deep),
      'rem': minutesIn(rem),
      'light': minutesIn(light),
      'awake': minutesIn(awake),
      'restless': 0,
    },
    'tl': timeline,
  };
}
