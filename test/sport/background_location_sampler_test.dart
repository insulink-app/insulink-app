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
}
