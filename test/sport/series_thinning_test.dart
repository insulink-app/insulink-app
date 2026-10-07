import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/training/series_thinning.dart';

void main() {
  test('a 30 min second-by-second series averages down to 30 points', () {
    final points = [
      for (var second = 0; second < 1800; second++)
        (x: second / 60, value: second.isEven ? 100.0 : 120.0),
    ];
    final thinned = const SeriesThinning(spanMinutes: 30).thin(points);
    expect(thinned.length, 30);
    expect(thinned.every((point) => point.value == 110), isTrue);
  });

  test('a short training is smoothed in 30 second stretches', () {
    expect(const SeriesThinning(spanMinutes: 5).bucketCount, 10);
  });

  test('a series already sparse enough is left as it is', () {
    final points = [(x: 1.0, value: 60.0), (x: 2.0, value: 70.0)];
    expect(const SeriesThinning(spanMinutes: 30).thin(points), points);
  });
}
