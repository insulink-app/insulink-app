import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_running_bolus.dart';

void main() {
  final started = DateTime(2026, 3, 1, 12);

  /// 4 U at the pod's normal rate: 80 pulses, two seconds apart.
  PodRunningBolus bolus({int pulses = 80, int eighthSeconds = 16}) =>
      PodRunningBolus(
        startedAt: started,
        pulses: pulses,
        eighthSecondsBetweenPulses: eighthSeconds,
      );

  group('a bolus is delivered one pulse at a time, not all at once', () {
    test('4 U at two seconds a pulse takes about two and a half minutes', () {
      expect(bolus().duration, const Duration(seconds: 160));
      expect(bolus().programmedUnits, closeTo(4.0, 1e-9));
    });

    test('nothing is delivered before the first pulse is out', () {
      expect(bolus().deliveredUnits(started), 0);
      expect(bolus().progress(started), 0);
      expect(bolus().isFinished(started), isFalse);
    });

    /// Floored on purpose: a pulse counts once it is OUT. Crediting the user with
    /// insulin still inside the pod would suppress a correction they need.
    test('a part-delivered pulse does not count yet', () {
      final part = started.add(const Duration(milliseconds: 1900));
      expect(bolus().deliveredUnits(part), 0);
      final justAfter = started.add(const Duration(milliseconds: 2100));
      expect(bolus().deliveredUnits(justAfter), closeTo(0.05, 1e-9));
    });

    test('half way through, half the dose is out', () {
      final half = started.add(const Duration(seconds: 80));
      expect(bolus().deliveredUnits(half), closeTo(2.0, 1e-9));
      expect(bolus().progress(half), closeTo(0.5, 1e-9));
    });

    test('it never reports more than it was programmed for', () {
      final late = started.add(const Duration(hours: 1));
      expect(bolus().deliveredUnits(late), closeTo(4.0, 1e-9));
      expect(bolus().progress(late), 1);
      expect(bolus().isFinished(late), isTrue);
      expect(bolus().remaining(late), Duration.zero);
    });

    /// A clock that went backwards must not produce negative insulin.
    test('a time before the start reads as nothing delivered', () {
      final before = started.subtract(const Duration(minutes: 5));
      expect(bolus().deliveredUnits(before), 0);
    });

    test('it survives a round trip through JSON', () {
      final restored = PodRunningBolus.fromJson(bolus().toJson());
      expect(restored.startedAt, started);
      expect(restored.pulses, 80);
      expect(restored.eighthSecondsBetweenPulses, 16);
    });

    test('the smallest possible bolus is one pulse', () {
      final single = bolus(pulses: 1);
      expect(single.programmedUnits, closeTo(0.05, 1e-9));
      expect(single.duration, const Duration(seconds: 2));
    });
  });
}
