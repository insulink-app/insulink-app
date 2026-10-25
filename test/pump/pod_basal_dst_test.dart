import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_basal_delivery.dart';

/// Every daylight-saving night must book basal and finish: the autumn night
/// repeats the hour from 2 to 3, and booking across it once looped forever and
/// froze the app. Only meaningful under a zone with daylight saving, which is
/// why CI runs the suite with `TZ=Europe/Berlin` (docs/DAYLIGHT_SAVING.md).
///
/// The sweep runs in its own isolate: a test timeout cannot interrupt a
/// synchronous endless loop, only a timeout waiting on another isolate turns a
/// regression into a failure instead of a hung run.
void main() {
  test('every window across every changeover night ends and adds up', () async {
    final wrong = await Isolate.run(
      _sweep,
    ).timeout(const Duration(seconds: 20));

    expect(wrong, isEmpty);
  });

  test('the hour after the repeated one bills its own rate', () {
    final rates = [for (var hour = 0; hour < 24; hour++) hour == 3 ? 2.0 : 1.0];
    final from = DateTime(2026, 10, 25, 2, 30).add(const Duration(hours: 1));
    final to = from.add(const Duration(hours: 1));

    expect(PodBasalDelivery(rates).unitsBetween(from, to), closeTo(1.5, 1e-9));
  });
}

/// Every quarter-hour window around each changeover of the EU rule from 2026
/// to 2030 (the last Sunday of March and of October) at a flat 1 U/h, named
/// "start + length" for each one that billed the wrong amount.
List<String> _sweep() {
  final delivery = PodBasalDelivery([
    for (var hour = 0; hour < 24; hour++) 1.0,
  ]);
  final starts = [
    for (var year = 2026; year <= 2030; year++)
      for (final month in [3, 10])
        for (var quarter = 0; quarter < 32; quarter++)
          _lastSunday(year, month)
              .subtract(const Duration(hours: 2))
              .add(Duration(minutes: 15 * quarter)),
  ];
  return [
    for (final from in starts)
      for (final minutes in const [15, 45, 90, 240])
        if (!_billsFlatHour(delivery, from, minutes)) '$from + $minutes min',
  ];
}

bool _billsFlatHour(PodBasalDelivery delivery, DateTime from, int minutes) {
  final to = from.add(Duration(minutes: minutes));
  return (delivery.unitsBetween(from, to) - minutes / 60).abs() < 1e-9;
}

DateTime _lastSunday(int year, int month) {
  final last = DateTime(year, month + 1, 0);
  return DateTime(year, month, last.day - last.weekday % 7);
}
