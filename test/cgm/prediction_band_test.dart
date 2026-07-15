import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/glucose_prediction.dart';

void main() {
  group('GlucosePrediction band round-trip', () {
    final base = DateTime.fromMillisecondsSinceEpoch(1750000000000);

    test('both bounds survive the cache', () {
      // The advisory and the band overlay read the CACHE, not the fetched
      // response — dropping the bounds here would silently return the low
      // trigger to the mean and collapse the band.
      final cached = GlucosePrediction.fromJson(
        GlucosePrediction(base, const [
          PredictionPoint(5, 120, lo: 98, hi: 141),
          PredictionPoint(10, 110, lo: 84, hi: 152),
        ]).toJson(),
      );
      expect(cached, isNotNull);
      expect(cached!.points.map((point) => point.lo), [98, 84]);
      expect(cached.points.map((point) => point.hi), [141, 152]);
      expect(cached.points.map((point) => point.mgdl), [120, 110]);
      expect(cached.base, base);
    });

    test('a point cached before the band existed degrades to null bounds', () {
      final legacy = GlucosePrediction.fromJson({
        'base': base.millisecondsSinceEpoch,
        'points': [
          {'o': 5, 'm': 120},
        ],
      });
      expect(legacy!.points.single.lo, isNull);
      expect(legacy.points.single.hi, isNull);
      expect(legacy.points.single.mgdl, 120);
    });
  });
}
