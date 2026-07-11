import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/google_health/heart_rate_measurement.dart';

void main() {
  test('8-bit bpm, no extra fields', () {
    final sample = HeartRateMeasurement.parse([0x00, 72]);
    expect(sample?.bpm, 72);
    expect(sample?.rrIntervalsMs, isEmpty);
  });

  test('16-bit bpm (flag bit0)', () {
    expect(HeartRateMeasurement.parse([0x01, 0x2C, 0x01])?.bpm, 300);
  });

  test('RR intervals decoded to ms, energy-expended skipped', () {
    // flags 0x18: energy-expended (2 bytes) + RR present. 1024 units => 1000 ms.
    final sample = HeartRateMeasurement.parse([
      0x18,
      60,
      0xFF,
      0xFF,
      0x00,
      0x04,
    ]);
    expect(sample?.bpm, 60);
    expect(sample?.rrIntervalsMs, [1000]);
  });

  test('malformed frames return null', () {
    expect(HeartRateMeasurement.parse([]), isNull);
    expect(HeartRateMeasurement.parse([0x01, 0x2C]), isNull);
  });
}
