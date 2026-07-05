import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/fitbit/fitbit_models.dart';

void main() {
  test('FitbitDay round-trips through JSON, keeping nulls out', () {
    const day = FitbitDay(dateKey: '2026-07-04', restingHr: 58, sleepMinutes: 440);
    final back = FitbitDay.fromJson(day.toJson());
    expect(back.dateKey, '2026-07-04');
    expect(back.restingHr, 58);
    expect(back.sleepMinutes, 440);
    expect(back.spo2, isNull);
    expect(day.toJson().containsKey('spo2'), isFalse);
  });

  test('formatSleepMinutes renders Xh Ym and – for null', () {
    expect(formatSleepMinutes(440), '7h 20m');
    expect(formatSleepMinutes(60), '1h 0m');
    expect(formatSleepMinutes(null), '–');
  });
}
