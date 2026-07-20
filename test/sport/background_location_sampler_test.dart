import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/training/background_location_sampler.dart';

void main() {
  group('isPlausibleFix', () {
    test('accepts a first, accurate fix', () {
      expect(isPlausibleFix(accuracyM: 8), isTrue);
    });

    test('rejects a poor-accuracy fix', () {
      expect(isPlausibleFix(accuracyM: 120), isFalse);
    });

    test('accepts a realistic move (10 m/s)', () {
      expect(isPlausibleFix(accuracyM: 8, meters: 40, seconds: 4), isTrue);
    });

    test('rejects a teleport jump', () {
      // 2 km in 4 s = 500 m/s.
      expect(isPlausibleFix(accuracyM: 8, meters: 2000, seconds: 4), isFalse);
    });

    test('cannot judge speed on a zero interval → accepts', () {
      expect(isPlausibleFix(accuracyM: 8, meters: 2000, seconds: 0), isTrue);
    });
  });

  group('gpsTierFor', () {
    test('a recording training always wins', () {
      expect(
        gpsTierFor(
          recording: true,
          hasActiveTraining: true,
          recentlyMoving: false,
          sustainedMoving: false,
        ),
        GpsTier.recording,
      );
    });

    test('brief movement without a training → sparse detect', () {
      expect(
        gpsTierFor(
          recording: false,
          hasActiveTraining: false,
          recentlyMoving: true,
          sustainedMoving: false,
        ),
        GpsTier.detect,
      );
    });

    test('sustained movement ramps up to the denser activeDetect', () {
      expect(
        gpsTierFor(
          recording: false,
          hasActiveTraining: false,
          recentlyMoving: true,
          sustainedMoving: true,
        ),
        GpsTier.activeDetect,
      );
    });

    test('at rest → no stream', () {
      expect(
        gpsTierFor(
          recording: false,
          hasActiveTraining: false,
          recentlyMoving: false,
          sustainedMoving: true,
        ),
        isNull,
      );
    });

    test('a paused training (active, not recording) streams nothing', () {
      expect(
        gpsTierFor(
          recording: false,
          hasActiveTraining: true,
          recentlyMoving: true,
          sustainedMoving: true,
        ),
        isNull,
      );
    });
  });
}
