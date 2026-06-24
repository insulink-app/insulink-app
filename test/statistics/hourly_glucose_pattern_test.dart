import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/statistics/patterns/hourly_glucose_pattern.dart';

/// Epoch-minute key for a reading at [hour]:[minute] on a fixed day.
int minuteKey(int hour, [int minute = 30]) =>
    DateTime(2024, 1, 1, hour, minute).millisecondsSinceEpoch ~/ 60000;

({int hour, double mean, double sd}) at(
  List<({int hour, double mean, double sd})> pattern,
  int hour,
) => pattern.firstWhere((point) => point.hour == hour);

void main() {
  group('HourlyGlucosePattern', () {
    test('empty readings yield an empty pattern', () {
      expect(HourlyGlucosePattern(const {}).build(), isEmpty);
    });

    test('spans all 24 hours when any data exists', () {
      final pattern = HourlyGlucosePattern({minuteKey(0): 100}).build();
      expect(pattern, hasLength(24));
      expect(
        pattern.map((point) => point.hour).toList(),
        List<int>.generate(24, (index) => index),
      );
    });

    test('mean and sd aggregate readings within the same hour', () {
      final pattern = HourlyGlucosePattern({
        minuteKey(0, 10): 90,
        minuteKey(0, 20): 110,
      }).build();
      expect(at(pattern, 0).mean, closeTo(100, 1e-9));
      expect(at(pattern, 0).sd, closeTo(10, 1e-9));
    });

    test('interpolates empty hours linearly between known ones (circular)', () {
      final pattern = HourlyGlucosePattern({
        minuteKey(0): 100,
        minuteKey(12): 200,
      }).build();
      expect(at(pattern, 0).mean, closeTo(100, 1e-9));
      expect(at(pattern, 12).mean, closeTo(200, 1e-9));
      // Midpoint hour 6 sits halfway; hour 3 a quarter of the way.
      expect(at(pattern, 6).mean, closeTo(150, 1e-9));
      expect(at(pattern, 3).mean, closeTo(125, 1e-9));
      // Hour 18 wraps: halfway from 12 back to 0.
      expect(at(pattern, 18).mean, closeTo(150, 1e-9));
    });
  });
}
