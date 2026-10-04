import 'dart:math';

import 'package:insulink/src/demo/demo_bonn_routes.dart';
import 'package:insulink/src/demo/demo_calendar.dart';
import 'package:insulink/src/demo/demo_route.dart';

/// One recorded demo training: when it ran, how hard, and the Bonn route it
/// followed.
typedef DemoCardioPlan = ({
  String type,
  int daysAgo,
  double hour,
  int heartRate,
  DemoRoute route,
});

/// Walks, a jog and a ride along real paths in Bonn, so the training detail page
/// has a route on the map and speed, heart rate and glucose over one timeline.
/// Each takes as long as its route needs at the type's pace.
class DemoCardio {
  DemoCardio({required this.calendar, required this.random});

  final DemoCalendar calendar;
  final Random random;

  static const int sampleSeconds = 10;
  static const double gpsNoiseDegrees = 0.00002;
  static const Map<String, double> kilometresPerHour = {
    'walk': 4.8,
    'jog': 10.5,
    'bike': 17.5,
  };

  final List<DemoCardioPlan> plans = [
    (
      type: 'walk',
      daysAgo: 1,
      hour: 15.25,
      heartRate: 105,
      route: DemoBonnRoutes.rheinaue,
    ),
    (
      type: 'jog',
      daysAgo: 3,
      hour: 17.0,
      heartRate: 150,
      route: DemoBonnRoutes.riverside,
    ),
    (
      type: 'bike',
      daysAgo: 6,
      hour: 10.5,
      heartRate: 128,
      route: DemoBonnRoutes.bridges,
    ),
    (
      type: 'walk',
      daysAgo: 9,
      hour: 18.0,
      heartRate: 102,
      route: DemoBonnRoutes.poppelsdorf,
    ),
  ];

  /// The trainings as API JSON, oldest first.
  late final List<Map<String, Object>> trainings = [
    for (final (index, plan) in plans.indexed.toList().reversed)
      _training(index, plan),
  ];

  /// When each training ran and how hard, for the heart-rate curve.
  List<({DateTime start, DateTime end, int heartRate})> get windows => [
    for (final plan in plans)
      (start: _start(plan), end: _end(plan), heartRate: plan.heartRate),
  ];

  DateTime _start(DemoCardioPlan plan) => calendar.at(
    calendar.today.subtract(Duration(days: plan.daysAgo)),
    plan.hour,
  );

  Duration _duration(DemoCardioPlan plan) => Duration(
    seconds: (plan.route.length / 1000 / kilometresPerHour[plan.type]! * 3600)
        .round(),
  );

  DateTime _end(DemoCardioPlan plan) => _start(plan).add(_duration(plan));

  Map<String, Object> _training(int index, DemoCardioPlan plan) => {
    'id': 'demo-training-$index',
    'type': plan.type,
    'start': _start(plan).millisecondsSinceEpoch,
    'end': _end(plan).millisecondsSinceEpoch,
    'dist': plan.route.length,
    'auto': false,
    'track': _track(plan),
  };

  List<Map<String, Object>> _track(DemoCardioPlan plan) {
    final samples = _duration(plan).inSeconds ~/ sampleSeconds;
    final start = _start(plan);
    return [
      for (var sample = 0; sample <= samples; sample++)
        _point(
          plan.route.at(plan.route.length * _progress(sample / samples)),
          start.add(Duration(seconds: sample * sampleSeconds)),
        ),
    ];
  }

  /// Share of the route covered after [share] of the time: a slightly uneven
  /// pace (faster, slower, faster) that still starts and ends on the route ends.
  double _progress(double share) =>
      share + 0.02 * sin(share * 6 * pi) * share * (1 - share);

  Map<String, Object> _point((double, double) position, DateTime at) => {
    'lat': position.$1 + (random.nextDouble() - 0.5) * gpsNoiseDegrees,
    'lng': position.$2 + (random.nextDouble() - 0.5) * gpsNoiseDegrees,
    't': at.millisecondsSinceEpoch,
  };
}
