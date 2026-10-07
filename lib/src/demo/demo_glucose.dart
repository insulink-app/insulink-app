import 'dart:math';

import 'package:insulink/src/demo/demo_drift.dart';
import 'package:insulink/src/demo/demo_glucose_range.dart';

/// A month of believable CGM readings every five minutes, up to [now]: a gentle
/// day rhythm, a rise after each meal and the occasional dip after it, plus a
/// smooth random drift ([DemoDrift]). Seeded, so every visitor sees the same month.
class DemoGlucose {
  DemoGlucose({required this.now, required this.random});

  final DateTime now;
  final Random random;

  static const int days = 30;
  static const Duration step = Duration(minutes: 5);
  static const List<double> mealHours = [7.5, 12.75, 19.25];
  static const double risePeakHours = 1.1;
  static const double dipPeakHours = 2.2;
  static const double mealWindowHours = 14;

  late final DateTime end = DateTime.fromMillisecondsSinceEpoch(
    now.millisecondsSinceEpoch ~/ step.inMilliseconds * step.inMilliseconds,
  );

  late final DateTime start = end.subtract(const Duration(days: days));

  late final List<double> _rises = [
    for (var index = 0; index < (days + 2) * mealHours.length; index++)
      55 + random.nextDouble() * 75,
  ];

  late final List<double> _dips = [
    for (var index = 0; index < (days + 2) * mealHours.length; index++)
      random.nextDouble() < 0.25 ? 30 + random.nextDouble() * 28 : 8,
  ];

  /// The readings, oldest first, as API history entries.
  /// Keeps the newest hours, and so the headline, in the target range.
  final DemoGlucoseRange range = const DemoGlucoseRange();

  late final Map<DateTime, int> readings = _generate();

  Map<DateTime, int> _generate() {
    final readings = <DateTime, int>{};
    final drift = DemoDrift(random);
    for (var time = start; !time.isAfter(end); time = time.add(step)) {
      drift.step();
      final value = range.easedTowards(shapeAt(time) + drift.value, time, end);
      readings[time] = value.round().clamp(48, 290);
    }
    return readings;
  }

  /// The curve without its random drift: the day rhythm plus the meals. The
  /// live feed (`demo_live_sensor.dart`) follows its slope past [end].
  double shapeAt(DateTime time) => _baseline(time) + _meals(time);

  /// A slow day rhythm peaking in the early morning (dawn phenomenon).
  double _baseline(DateTime time) {
    final hour = time.hour + time.minute / 60;
    return 126 + 14 * sin((hour - 1) / 24 * 2 * pi);
  }

  double _meals(DateTime time) {
    var total = 0.0;
    for (var meal = 0; meal < mealHours.length; meal++) {
      final hours = _hoursSince(time, mealHours[meal]);
      final index = _mealDay(time, hours) * mealHours.length + meal;
      total += _mealCurve(hours, index);
    }
    return total;
  }

  /// Which calendar day the meal [hoursSince] before [time] was eaten on, so one
  /// meal keeps its size for its whole curve. Counted from the day BEFORE
  /// [start]'s: the first readings can still carry the previous evening's meal
  /// (a start before about nine in the morning is within its window).
  int _mealDay(DateTime time, double hoursSince) {
    final eaten = time.subtract(Duration(minutes: (hoursSince * 60).round()));
    final eatenDay = DateTime.utc(eaten.year, eaten.month, eaten.day);
    final firstDay = DateTime.utc(start.year, start.month, start.day - 1);
    return eatenDay.difference(firstDay).inDays;
  }

  double _hoursSince(DateTime time, double mealHour) {
    final hours = time.hour + time.minute / 60 - mealHour;
    return hours < 0 ? hours + 24 : hours;
  }

  /// A rise that starts gently and peaks about [risePeakHours] after eating,
  /// then a smaller dip below the baseline once the bolus outlasts the carbs.
  /// Both have faded to almost nothing by [mealWindowHours]; cutting a curve off
  /// while its dip is still deep made the line jump up hours after dinner. Meals
  /// past the generated month (the live feed) reuse the sizes from its start.
  double _mealCurve(double hours, int index) {
    if (hours > mealWindowHours) {
      return 0;
    }
    final share = hours / risePeakHours;
    final rise =
        _rises[index % _rises.length] * share * share * exp(2 * (1 - share));
    final dip =
        _dips[index % _dips.length] *
        (hours / dipPeakHours) *
        exp(1 - hours / dipPeakHours);
    return rise - dip;
  }

  /// mg/dL per minute over the last five minutes, for the headline arrow.
  double get trendPerMinute =>
      (readings[end]! - readings[end.subtract(step)]!) / step.inMinutes;

  /// The mg/dL closest to [time], for meals logged against the curve.
  int valueAt(DateTime time) {
    final aligned = DateTime.fromMillisecondsSinceEpoch(
      time.millisecondsSinceEpoch ~/ step.inMilliseconds * step.inMilliseconds,
    );
    return readings[aligned] ?? 110;
  }
}
