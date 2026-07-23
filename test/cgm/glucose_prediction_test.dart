import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/glucose_prediction.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final base = DateTime(2026, 7, 9, 16, 0);

  test('json round-trip keeps the base and the band bounds', () {
    final prediction = GlucosePrediction(base, const [
      PredictionPoint(5, 120, lo: 105, hi: 140),
      PredictionPoint(10, 130),
    ]);

    final restored = GlucosePrediction.fromJson(prediction.toJson())!;

    expect(restored.base, base);
    expect(restored.points.first.offsetMin, 5);
    expect(restored.points.first.mgdl, 120);
    expect(restored.points.first.lo, 105);
    expect(restored.points.first.hi, 140);
    expect(restored.points.last.lo, isNull);
    expect(restored.points.last.hi, isNull);
  });

  test('a malformed or empty cache degrades to null instead of throwing', () {
    expect(GlucosePrediction.fromJson({}), isNull);
    expect(GlucosePrediction.fromJson({'base': 'nope', 'points': []}), isNull);
    expect(
      GlucosePrediction.fromJson({'base': base.millisecondsSinceEpoch}),
      isNull,
    );
    expect(
      GlucosePrediction.fromJson({
        'base': base.millisecondsSinceEpoch,
        'points': [],
      }),
      isNull,
    );
  });

  test('the cache survives a save/load and is cleared by saving null', () async {
    installSecureStorageMock();
    final cache = PredictionCache();

    expect(await cache.load(), isNull);

    await cache.save(
      GlucosePrediction(base, const [PredictionPoint(15, 90, lo: 75, hi: 110)]),
    );
    final loaded = (await cache.load())!;

    expect(loaded.base, base);
    expect(loaded.points.single.mgdl, 90);
    expect(loaded.points.single.lo, 75);

    await cache.save(null);
    expect(await cache.load(), isNull);
  });
}
