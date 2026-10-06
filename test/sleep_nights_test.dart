import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/sleep_nights.dart';

void main() {
  int at(int day, int hour, int minute) =>
      DateTime(2026, 10, day, hour, minute).millisecondsSinceEpoch;
  SleepSegment seg(SleepStage stage, int from, int to) =>
      SleepSegment(stage: stage, startMs: from, endMs: to);

  /// A night across midnight is ONE night, not two stretches on two days.
  test('a night across midnight stays together', () {
    final night = [
      seg(SleepStage.light, at(5, 23, 52), at(6, 0, 30)),
      seg(SleepStage.deep, at(6, 0, 30), at(6, 2, 0)),
      seg(SleepStage.light, at(6, 2, 0), at(6, 7, 41)),
    ];
    final nights = SleepNights(night).all;
    expect(nights, hasLength(1));
    expect(nights.single.first.startMs, at(5, 23, 52));
    expect(nights.single.endMs, at(6, 7, 41));
  });

  /// The stored day that mixed two nights: the morning of one night and the
  /// first minutes of the next. The night shown is the long one, so it no
  /// longer reads as falling asleep at 23:59 and waking at 23:52.
  test('a stray stretch of the next night is not the night', () {
    final mixed = [
      seg(SleepStage.light, at(6, 0, 10), at(6, 3, 0)),
      seg(SleepStage.deep, at(6, 3, 0), at(6, 7, 30)),
      seg(SleepStage.light, at(6, 23, 52), at(6, 23, 59)),
    ];
    final nights = SleepNights(mixed);
    expect(nights.all, hasLength(2));
    expect(nights.longest.first.startMs, at(6, 0, 10));
    expect(nights.longest.endMs, at(6, 7, 30));
  });

  test('a short wake inside the night does not split it', () {
    final night = [
      seg(SleepStage.light, at(6, 0, 0), at(6, 2, 0)),
      seg(SleepStage.light, at(6, 2, 40), at(6, 6, 0)),
    ];
    expect(SleepNights(night).all, hasLength(1));
  });
}
