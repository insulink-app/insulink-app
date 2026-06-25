import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sensor/control/sensor_lifespan.dart';

/// Standard G7: rated 10 days + ~12 h grace = 907200 s.
const g7Session = 907200;

SensorLifespan after(Duration elapsed, {int session = g7Session}) {
  final start = DateTime(2024, 1, 1, 12);
  return SensorLifespan(
    start: start,
    sessionLengthSec: session,
    now: start.add(elapsed),
  );
}

void main() {
  group('SensorLifespan.totalDays', () {
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

  group('expired', () {
    test('past the session end the sensor is expired', () {
      final life = after(const Duration(days: 11));
      expect(life.expired, isTrue);
      expect(life.hoursMode, isFalse);
      expect(life.remainingSecs, lessThanOrEqualTo(0));
    });
  });
}
