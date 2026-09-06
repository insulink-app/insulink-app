import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/base/device_lifespan.dart';

/// Standard G7: rated 10 days + ~12 h grace = 907200 s.
const g7Session = 907200;

DeviceLifespan after(Duration elapsed, {int session = g7Session}) {
  final start = DateTime(2024, 1, 1, 12);
  return DeviceLifespan(
    start: start,
    sessionLengthSec: session,
    now: start.add(elapsed),
  );
}

void main() {
  group('DeviceLifespan.totalDays', () {
    test('floors the 10.5-day session to 10 whole days (not 11)', () {
      expect(after(Duration.zero).totalDays, 10);
    });

    test('reflects shorter sessions', () {
      expect(after(Duration.zero, session: 7 * 86400).totalDays, 7);
    });
  });

  group('day mode (more than a day left)', () {
    test('shows day granularity and a full bar at session start', () {
      final life = after(Duration.zero);
      expect(life.hoursMode, isFalse);
      expect(life.totalSegments, 10);
      expect(life.filledSegments, 10);
      expect(life.expired, isFalse);
    });

    test('fills fewer day-segments as time passes (partial day rounds up)', () {
      // 3.5 days elapsed → ~7 days (incl. grace) remain → ceil = 7 filled.
      final life = after(const Duration(days: 3, hours: 12));
      expect(life.hoursMode, isFalse);
      expect(life.filledSegments, 7);
    });
  });

  group('hour mode (final 24 h)', () {
    test('switches to 24 hour-segments once <= 1 day remains', () {
      // 9 days 18 h elapsed → 18 h remain (< 24 h) → hour mode.
      final life = after(const Duration(days: 9, hours: 18));
      expect(life.hoursMode, isTrue);
      expect(life.totalSegments, 24);
      expect(life.filledSegments, 18); // 18 h remaining, ceil
    });

    test('boundary: exactly 24 h remaining is still hour mode', () {
      final life = after(const Duration(days: 9, hours: 12)); // 24h left
      expect(life.hoursMode, isTrue);
      expect(life.filledSegments, 24);
    });
  });

  group('grace period (rated lifetime up, sensor still reading)', () {
    test('not in grace while rated days remain', () {
      expect(after(const Duration(days: 9, hours: 18)).inGrace, isFalse);
    });

    test('enters grace once past the rated 10 days', () {
      // 10 d 3 h elapsed → 9 h of the 12 h grace remain.
      final life = after(const Duration(days: 10, hours: 3));
      expect(life.inGrace, isTrue);
      expect(life.expired, isFalse);
      expect(life.graceHoursLeft, 9);
    });

    test('grace window is ~12 h', () {
      expect(after(Duration.zero).graceSecs, 43200);
    });

    test('no longer in grace once expired', () {
      expect(after(const Duration(days: 11)).inGrace, isFalse);
    });
  });

  group('minute mode (final hour)', () {
    test('the last hour counts in minutes, not in a flat "1 h"', () {
      // 10 d 11 h 35 min elapsed → 25 min of the 12 h grace remain.
      final life = after(const Duration(days: 10, hours: 11, minutes: 35));
      expect(life.minutesMode, isTrue);
      expect(life.minutesLeft, 25);
      // The bar keeps its hour segments; only the label changes.
      expect(life.hoursMode, isTrue);
      expect(life.totalSegments, 24);
    });

    test('a partial minute still counts, so it never reads zero', () {
      final life = after(
        const Duration(days: 10, hours: 11, minutes: 59, seconds: 30),
      );
      expect(life.minutesLeft, 1);
    });

    test('boundary: exactly one hour left is already minute mode', () {
      final life = after(const Duration(days: 10, hours: 11));
      expect(life.minutesMode, isTrue);
      expect(life.minutesLeft, 60);
    });

    test('more than an hour left is not minute mode', () {
      final life = after(const Duration(days: 10, hours: 10, minutes: 59));
      expect(life.minutesMode, isFalse);
    });

    test('an expired device is not in minute mode', () {
      expect(after(const Duration(days: 11)).minutesMode, isFalse);
    });
  });

  group('expired', () {
    test('past the session end the sensor is expired', () {
      final life = after(const Duration(days: 11));
      expect(life.expired, isTrue);
      expect(life.hoursMode, isFalse);
      expect(life.remainingSecs, lessThanOrEqualTo(0));
    });
  });
}
