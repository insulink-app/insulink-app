import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/google_health/band/band_signal.dart';

void main() {
  test('the signal falls into three steps, each lighting its own bars', () {
    expect([-49, -70, -71, -82, -83].map(BandSignal.of), [
      BandSignal.good,
      BandSignal.good,
      BandSignal.medium,
      BandSignal.medium,
      BandSignal.poor,
    ]);
    expect(BandSignal.values.map((signal) => signal.bars), [3, 2, 1]);
  });
}
