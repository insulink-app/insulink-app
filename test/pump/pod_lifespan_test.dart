import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/base/device_lifespan.dart';
import 'package:insulink/src/overview/overview_pod_life.dart';

void main() {
  final activated = DateTime(2026, 3, 1, 8, 0);

  DeviceLifespan podAfter(Duration elapsed) => DeviceLifespan(
        start: activated,
        sessionLengthSec: OverviewPodLife.podLifetimeSeconds,
        now: activated.add(elapsed),
      );

  group("a pod's 80 hours read as three rated days plus grace", () {
    test('a fresh pod shows three day segments, all filled', () {
      final life = podAfter(Duration.zero);
      expect(life.totalDays, 3);
      expect(life.totalSegments, 3);
      expect(life.filledSegments, 3);
      expect(life.expired, isFalse);
      expect(life.inGrace, isFalse);
    });

    test('the grace window is the eight hours past the rated three days', () {
      expect(podAfter(Duration.zero).graceSecs, 8 * 3600);
    });

    test('two days in, one rated day is left', () {
      final life = podAfter(const Duration(hours: 48));
      expect(life.filledSegments, 2);
      expect(life.inGrace, isFalse);
    });

    test('inside the final day it switches to hour segments', () {
      final life = podAfter(const Duration(hours: 60));
      expect(life.hoursMode, isTrue);
      expect(life.totalSegments, 24);
      expect(life.filledSegments, 20);
    });

    test('past the rated 72 hours it is in grace, not expired', () {
      final life = podAfter(const Duration(hours: 74));
      expect(life.inGrace, isTrue);
      expect(life.expired, isFalse);
      expect(life.graceHoursLeft, 6);
    });

    test('at 80 hours the pod is expired', () {
      expect(podAfter(const Duration(hours: 80)).expired, isTrue);
      expect(podAfter(const Duration(hours: 80)).inGrace, isFalse);
    });

    test('past expiry it stays expired rather than wrapping', () {
      final life = podAfter(const Duration(hours: 200));
      expect(life.expired, isTrue);
      expect(life.filledSegments, 0);
    });
  });

  group('a pod that reports a different lifetime is honoured', () {
    test('a shorter reported lifetime shortens the bar', () {
      final life = DeviceLifespan(
        start: activated,
        sessionLengthSec: 48 * 3600,
        now: activated,
      );
      expect(life.totalDays, 2);
      expect(life.filledSegments, 2);
    });
  });

  group('the low-reservoir threshold', () {
    test('is a round ten units, so a pod change can still be planned', () {
      expect(OverviewPodReservoir.lowUnits, 10.0);
    });
  });
}
