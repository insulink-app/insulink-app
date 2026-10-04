import 'dart:math';

import 'package:insulink/src/demo/demo_activity.dart';
import 'package:insulink/src/demo/demo_calendar.dart';
import 'package:insulink/src/demo/demo_cardio.dart';
import 'package:insulink/src/demo/demo_events.dart';
import 'package:insulink/src/demo/demo_glucose.dart';
import 'package:insulink/src/demo/demo_health.dart';
import 'package:insulink/src/demo/demo_nutrition.dart';
import 'package:insulink/src/demo/demo_sport.dart';

/// The account the browser demo is signed in to: every collection the app pulls
/// on start, generated once around [now] from a fixed seed, answered in the API's
/// response shapes by [respond].
class DemoAccount {
  DemoAccount(this.now);

  final DateTime now;

  final Random _random = Random(2026);

  late final DemoCalendar _calendar = DemoCalendar(now);
  late final DemoGlucose glucose = DemoGlucose(now: now, random: _random);
  late final DemoCardio _cardio = DemoCardio(
    calendar: _calendar,
    random: _random,
  );
  late final DemoSport _sport = DemoSport(calendar: _calendar, random: _random);
  late final DemoActivity _activity = DemoActivity(
    calendar: _calendar,
    random: _random,
  );
  late final DemoHealth _health = DemoHealth(
    calendar: _calendar,
    random: _random,
    efforts: _cardio.windows,
  );
  late final DemoNutrition _nutrition = DemoNutrition(
    calendar: _calendar,
    random: _random,
    glucose: glucose,
  );

  late final Map<String, Map<String, Object>> _routes = {
    '/glucose/history/': _list('entries', _glucoseEntries),
    '/event/history/': _list('entries', DemoEvents(glucose.readings).entries),
    '/sport/measurements/find/': _list('entries', _activity.entries),
    '/sport/exercises/find/': _list('exercises', _sport.exercises),
    '/sport/routines/find/': _list('routines', _sport.routines),
    '/sport/workouts/find/': _list('workouts', _sport.workouts),
    '/sport/trainings/find/': _list('trainings', _cardio.trainings),
    '/nutrition/meals/find/': _list('meals', _nutrition.meals),
    '/nutrition/drinks/find/': _list('drinks', _nutrition.drinks),
    '/inventory/items/find/': _list('items', _nutrition.inventory),
    '/health/days/find/': _list('days', _health.healthDays),
    '/health/pulse/find/': _list('samples', _health.pulse),
    '/health/hba1c/find/': _list('readings', _health.hba1c),
    '/pump/register/': {'success': true, 'pump_id': 1},
    '/sensor/register/': {'success': true, 'sensor_id': 1},
  };

  List<Map<String, Object>> get _glucoseEntries => [
    for (final MapEntry(key: time, value: value) in glucose.readings.entries)
      {'time': time.millisecondsSinceEpoch, 'value': value},
  ];

  /// The newest heart-rate sample (`t`, `b`), shown as the live band reading.
  Map<String, int> get latestPulse => _health.pulse.last;

  Map<String, Object> _list(String key, List<Object> items) => {
    'success': true,
    key: items,
  };

  /// The answer to one API call. Paths the demo has no data for report a plain
  /// failure on reads, so the app keeps its defaults, and success on writes, so
  /// nothing queues a retry.
  Map<String, Object> respond(String method, String path) =>
      _routes[path.replaceFirst('/v1', '')] ?? {'success': method == 'POST'};
}
