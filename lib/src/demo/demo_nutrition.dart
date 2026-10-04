import 'dart:math';

import 'package:insulink/src/demo/demo_calendar.dart';
import 'package:insulink/src/demo/demo_glucose.dart';

/// The demo's meals (logged at the times the glucose curve rises, with the
/// value it had then and a matching bolus), the water drunk per day, and the
/// sensor and pod stock in the inventory.
class DemoNutrition {
  DemoNutrition({
    required this.calendar,
    required this.random,
    required this.glucose,
  });

  final DemoCalendar calendar;
  final Random random;
  final DemoGlucose glucose;

  static const int days = 14;
  static const double gramsPerUnit = 12;
  static const List<int> sips = [250, 330, 500];

  /// Meals as API JSON, one per meal time that has already passed.
  late final List<Map<String, Object>> meals = [
    for (final day in calendar.lastDays(days))
      for (final hour in DemoGlucose.mealHours)
        if (calendar.isPast(calendar.at(day, hour)))
          _meal(calendar.at(day, hour)),
  ];

  Map<String, Object> _meal(DateTime time) {
    final carbs = 25 + random.nextInt(12) * 5;
    return {
      'time': time.millisecondsSinceEpoch,
      'carbs': carbs,
      'glucose': glucose.valueAt(time),
      'bolus': (carbs / gramsPerUnit * 10).round() / 10,
      'entries': <Object>[],
      'delivered_by_pump': false,
    };
  }

  /// Drinks as API JSON (`at`, `ml`, `kind`), spread over each day's waking
  /// hours. The morning glass is always there, so today never reads 0 L.
  late final List<Map<String, Object>> drinks = [
    for (final day in calendar.lastDays(days))
      for (final hour in [8.0, 10.5, 13.0, 15.5, 18.0, 20.5])
        if (calendar.isPast(calendar.at(day, hour)) &&
            (hour == 8.0 || random.nextDouble() < 0.8))
          {
            'at': calendar.at(day, hour).millisecondsSinceEpoch,
            'ml': sips[random.nextInt(sips.length)],
            'kind': 'free',
          },
  ];

  /// Inventory items as API JSON: spare sensors and pods.
  late final List<Map<String, Object>> inventory = [
    _item('demo-g7', 'Dexcom G7', 'sensor', 6, 10, 10, sensorBrand: 'dexcom'),
    _item(
      'demo-pods',
      'Omnipod DASH',
      'pump',
      12,
      20,
      3,
      pumpBrand: 'omnipod_dash',
    ),
  ];

  Map<String, Object> _item(
    String id,
    String name,
    String type,
    int stock,
    int baseStock,
    int daysPerUnit, {
    String? sensorBrand,
    String? pumpBrand,
  }) => {
    'id': id,
    'name': name,
    'type': type,
    'stock': stock,
    'base_stock': baseStock,
    'days_per_unit': daysPerUnit,
    'anchor_ms': calendar.today.millisecondsSinceEpoch,
    'sensor_brand': ?sensorBrand,
    'pump_brand': ?pumpBrand,
    'deliveries': <Object>[],
  };
}
