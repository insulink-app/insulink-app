import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';

/// The bolus calculator works in real numbers and lands on values like
/// 1.01502045 U, which the pod cannot meter. Every dose carried out without a
/// human reading it off a rounded field has to be snapped first, and the snapped
/// value has to survive [PodBolusAmount.fromUnits] — which is the check that
/// actually failed in the field.
void main() {
  test('a calculated dose snaps onto the pulse grid and is deliverable', () {
    final units = PodBolusAmount.snapToPulse(1.01502045);
    expect(units, closeTo(1.0, 1e-9));
    expect(PodBolusAmount.fromUnits(units).pulses, 20);
  });

  test('it snaps DOWN, never up onto insulin nobody asked for', () {
    expect(PodBolusAmount.snapToPulse(1.049), closeTo(1.0, 1e-9));
    expect(PodBolusAmount.snapToPulse(1.05), closeTo(1.05, 1e-9));
    expect(PodBolusAmount.snapToPulse(1.099), closeTo(1.05, 1e-9));
  });

  test('a dose already on the grid is left alone', () {
    for (final units in const [0.05, 0.5, 2.0, 3.35]) {
      expect(PodBolusAmount.snapToPulse(units), closeTo(units, 1e-9));
      expect(() => PodBolusAmount.fromUnits(units), returnsNormally);
    }
  });

  test('less than one pulse snaps to nothing rather than to a pulse', () {
    expect(PodBolusAmount.snapToPulse(0.04), 0);
    expect(PodBolusAmount.snapToPulse(0), 0);
    expect(PodBolusAmount.snapToPulse(-1), 0);
    expect(PodBolusAmount.snapToPulse(double.nan), 0);
  });

  test('every snapped value across the range is accepted by fromUnits', () {
    for (var thousandths = 1; thousandths <= 30000; thousandths += 7) {
      final units = PodBolusAmount.snapToPulse(thousandths / 1000);
      if (units > 0) {
        expect(
          () => PodBolusAmount.fromUnits(units),
          returnsNormally,
          reason: 'snapped $units U from ${thousandths / 1000} U',
        );
      }
    }
  });
}
