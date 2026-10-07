import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/overview/range_scale.dart';

void main() {
  const scale = RangeScale(mgdl: null);

  test('places a value proportionally between 40 and 250', () {
    expect(scale.fractionOf(40), 0);
    expect(scale.fractionOf(145), closeTo(0.5, 1e-9));
    expect(scale.fractionOf(250), 1);
  });

  test('pins values beyond the scale to its ends', () {
    expect(scale.fractionOf(25), 0);
    expect(scale.fractionOf(400), 1);
  });
}
