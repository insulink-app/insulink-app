import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_reservoir_level.dart';

void main() {
  PodReservoirLevel read(double? units) =>
      PodReservoirLevel(hasStatus: true, units: units);

  group('the reservoir bar fills from what the pod actually said', () {
    /// The pod stops measuring around 50 U and sends a sentinel instead, so a
    /// full pod reports no number at all. The bar has to read that as full, not
    /// as empty.
    test('above its measuring range the bar is full, with no figure to print', () {
      final level = read(null);
      expect(level.fraction, 1);
      expect(level.isAboveRange, isTrue);
      expect(level.hasNumber, isFalse);
      expect(level.isLow, isFalse);
    });

    /// The same missing number means the opposite before anything was read, which
    /// is why the model is told whether a status exists at all.
    test('an unread pod is empty track, not a full one', () {
      const level = PodReservoirLevel(hasStatus: false, units: null);
      expect(level.fraction, 0);
      expect(level.isAboveRange, isFalse);
      expect(level.hasNumber, isFalse);
    });

    test('a reading fills its share of the measuring range', () {
      expect(read(25).fraction, closeTo(0.5, 1e-9));
      expect(read(50).fraction, closeTo(1.0, 1e-9));
      expect(read(0).fraction, 0);
    });

    /// A pod that somehow reports more than the range it can measure must not
    /// overflow the track.
    test('a reading past the range is clamped, never overdrawn', () {
      expect(read(200).fraction, 1);
    });

    /// A round ten units, so a pod change can still be planned rather than
    /// scrambled for.
    test('low is the warning line, and only for a number the pod gave', () {
      expect(PodReservoirLevel.lowUnits, 10.0);
      expect(read(10).isLow, isTrue);
      expect(read(9.95).isLow, isTrue);
      expect(read(10.05).isLow, isFalse);
      expect(read(null).isLow, isFalse);
      expect(const PodReservoirLevel(hasStatus: false, units: null).isLow, isFalse);
    });
  });
}
