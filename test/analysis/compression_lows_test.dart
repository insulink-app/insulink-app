import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/analysis/compression/compression_lows.dart';
import 'package:insulink/src/analysis/compression/night_sleep.dart';

/// A compression low is a sleep-time dip glucose leaves faster than a body can
/// without food; a slow real low, a low while awake and one with a meal stay.
void main() {
  final evening = DateTime(2026, 10, 27);
  int minute(int hour, int min) =>
      DateTime(
        2026,
        10,
        hour < 12 ? 28 : 27,
        hour,
        min,
      ).millisecondsSinceEpoch ~/
      60000;

  /// Awake at 80 bpm until 23:30, asleep at 60 until 06:15, awake again.
  Map<int, int> pulse() => {
    for (var at = minute(20, 0); at < minute(11, 0); at++)
      at: at >= minute(23, 30) && at < minute(6, 15) ? 60 : 80,
  };

  /// One reading every five minutes from [from], the values in order.
  SplayTreeMap<int, int> readings(int from, List<int> values) =>
      SplayTreeMap.of({
        for (var index = 0; index < values.length; index++)
          from + index * 5: values[index],
      });

  test('the sleep is read off the pulse', () {
    final sleep = const NightSleepDetector().detect(evening, pulse())!;

    int minutesOff(DateTime at, DateTime expected) =>
        at.difference(expected).inMinutes.abs();

    expect(minutesOff(sleep.from, DateTime(2026, 10, 27, 23, 30)), lessThan(3));
    expect(minutesOff(sleep.to, DateTime(2026, 10, 28, 6, 15)), lessThan(3));
  });

  final sleeps = [const NightSleepDetector().detect(evening, pulse())!];

  test('a dip out of which glucose jumps back is a compression', () {
    final night = readings(minute(3, 37), [90, 94, 94, 66, 50, 59, 75, 95]);

    final dips = CompressionLows(
      sleeps: sleeps,
      mealMinutes: const [],
    ).find(night);

    expect(dips.single.nadirMgdl, 50);
    expect(dips.single.fromMinute, minute(3, 47));
    expect(dips.single.toMinute, minute(4, 12));
  });

  test('a slow low while asleep is real', () {
    final night = readings(minute(1, 0), [90, 84, 78, 72, 66, 63, 64, 66, 69]);

    expect(
      CompressionLows(sleeps: sleeps, mealMinutes: const []).find(night),
      isEmpty,
    );
  });

  test('the same dip while awake or after a meal stays', () {
    final dip = [90, 94, 94, 66, 50, 59, 75, 95];

    expect(
      CompressionLows(
        sleeps: sleeps,
        mealMinutes: const [],
      ).find(readings(minute(22, 2), dip)),
      isEmpty,
    );
    expect(
      CompressionLows(
        sleeps: sleeps,
        mealMinutes: [minute(3, 55)],
      ).find(readings(minute(3, 37), dip)),
      isEmpty,
    );
  });

  /// The night of [pulse], then awake at 80 with an hour on the couch at 60
  /// from 14:00 to 15:00 and ten minutes at 60 from 17:00.
  Map<int, int> dayPulse() {
    final base = DateTime(2026, 10, 28).millisecondsSinceEpoch ~/ 60000;
    bool resting(int at) =>
        (at >= base + 14 * 60 && at < base + 15 * 60) ||
        (at >= base + 17 * 60 && at < base + 17 * 60 + 10);
    return {
      ...pulse(),
      for (var at = base + 11 * 60; at < base + 20 * 60; at++)
        at: resting(at) ? 60 : 80,
    };
  }

  test('a long rest by day counts, a short one does not', () {
    final found = const NightSleepDetector().detectAll(evening, dayPulse());

    expect(found, hasLength(2));
    final rest = found.last;
    expect(rest.contains(DateTime(2026, 10, 28, 14, 30)), isTrue);
    expect(rest.contains(DateTime(2026, 10, 28, 17, 5)), isFalse);
  });

  test('a compression on the couch is filtered', () {
    final base = DateTime(2026, 10, 28).millisecondsSinceEpoch ~/ 60000;
    final couch = readings(base + 14 * 60 + 17, [
      90,
      94,
      94,
      66,
      50,
      59,
      75,
      95,
    ]);

    final dips = CompressionLows(
      sleeps: const NightSleepDetector().detectAll(evening, dayPulse()),
      mealMinutes: const [],
    ).find(couch);

    expect(dips, hasLength(1));
  });
}
