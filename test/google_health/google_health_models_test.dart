import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/google_health/google_health_models.dart';

void main() {
  test('GoogleHealthDay round-trips through JSON, keeping nulls out', () {
    const day = GoogleHealthDay(dateKey: '2026-07-04', restingHr: 58, sleepMinutes: 440);
    final back = GoogleHealthDay.fromJson(day.toJson());
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

  test('a day with a sleep timeline round-trips through JSON', () {
    const day = GoogleHealthDay(
      dateKey: '2026-07-04',
      sleepMinutes: 100,
      sleepTimeline: [
        SleepSegment(stage: SleepStage.light, startMs: 1000, endMs: 2000),
        SleepSegment(stage: SleepStage.deep, startMs: 2000, endMs: 3500),
      ],
    );
    final back = GoogleHealthDay.fromJson(day.toJson());
    expect(back.sleepTimeline, hasLength(2));
    expect(back.sleepTimeline![1].stage, SleepStage.deep);
    expect(back.sleepTimeline![1].endMs, 3500);
  });

  test('a day without a timeline keeps the key out of JSON', () {
    const day = GoogleHealthDay(dateKey: '2026-07-04', sleepMinutes: 100);
    expect(day.toJson().containsKey('tl'), isFalse);
    expect(GoogleHealthDay.fromJson(day.toJson()).sleepTimeline, isNull);
  });
}
