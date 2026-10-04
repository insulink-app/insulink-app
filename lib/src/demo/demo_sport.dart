import 'dart:math';

import 'package:insulink/src/demo/demo_calendar.dart';

/// The demo's strength training: a handful of exercises, three routines built
/// from them and a month of logged workouts, in the API's JSON shapes.
class DemoSport {
  DemoSport({required this.calendar, required this.random});

  final DemoCalendar calendar;
  final Random random;

  static const int days = 30;

  final List<Map<String, Object>> exercises = [
    {'id': 'demo-warmup', 'name': 'Warm-up', 'kind': 'timed'},
    {'id': 'demo-pushups', 'name': 'Push-ups', 'kind': 'reps'},
    {'id': 'demo-squats', 'name': 'Squats', 'kind': 'reps'},
    {'id': 'demo-plank', 'name': 'Plank', 'kind': 'timed'},
    {'id': 'demo-curls', 'name': 'Dumbbell curls', 'kind': 'weighted'},
    {'id': 'demo-lunges', 'name': 'Lunges', 'kind': 'reps'},
    {'id': 'demo-pullups', 'name': 'Pull-ups', 'kind': 'reps'},
  ];

  late final List<Map<String, Object>> routines = [
    _routine('demo-full', 'Full body', [
      ('demo-warmup', 1, 300, 0.0),
      ('demo-pushups', 3, 15, 0.0),
      ('demo-squats', 3, 20, 0.0),
      ('demo-curls', 3, 12, 10.0),
      ('demo-pullups', 3, 8, 0.0),
      ('demo-plank', 2, 60, 0.0),
    ]),
    _routine('demo-morning', 'Morning routine', [
      ('demo-pushups', 2, 15, 0.0),
      ('demo-plank', 2, 45, 0.0),
    ]),
    _routine('demo-legs', 'Short leg day', [
      ('demo-squats', 3, 20, 0.0),
      ('demo-lunges', 3, 12, 0.0),
    ]),
  ];

  Map<String, Object> _routine(
    String id,
    String name,
    List<(String, int, int, double)> items,
  ) => {
    'id': id,
    'name': name,
    'items': [
      for (final (exercise, sets, target, weight) in items)
        {
          'id': '$id-$exercise',
          'ex': exercise,
          'sets': sets,
          'target': target,
          'weight': weight,
          'rest': 60,
        },
    ],
  };

  /// A workout every two to three days, alternating the routines.
  late final List<Map<String, Object>> workouts = [
    for (final (index, day) in calendar.lastDays(days).indexed)
      if (index % 3 != 1 && calendar.isPast(calendar.at(day, 18)))
        _workout(index, calendar.at(day, 7.75 + (index % 2) * 10)),
  ];

  Map<String, Object> _workout(int index, DateTime started) {
    final routine = routines[index % routines.length];
    var clock = started;
    final sets = <Map<String, Object?>>[];
    for (final item in routine['items'] as List<Map<String, Object>>) {
      for (var set = 0; set < (item['sets'] as int); set++) {
        sets.add(_set(item, clock));
        clock = clock.add(const Duration(seconds: 120));
      }
    }
    return {
      'id': 'demo-workout-$index',
      'routine': routine['id']!,
      'started': started.millisecondsSinceEpoch,
      'sets': sets,
    };
  }

  Map<String, Object?> _set(Map<String, Object> item, DateTime at) {
    final timed =
        (item['ex'] as String) == 'demo-plank' ||
        (item['ex'] as String) == 'demo-warmup';
    final target = item['target'] as int;
    final achieved = target - 2 + random.nextInt(5);
    return {
      'ex': item['ex'],
      'reps': timed ? null : achieved,
      'secs': timed ? target : null,
      'kg': item['weight'] == 0.0 ? null : item['weight'],
      'dur': timed ? target : achieved * 3,
      'rest': 60,
      'ts': at.millisecondsSinceEpoch,
    };
  }
}
