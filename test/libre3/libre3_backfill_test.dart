import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/libre3/libre3_connection.dart';

void main() {
  // liveSecs is seconds-since-start; life count = liveSecs / 60.
  group('Libre3Connection.backfillStartLifeCount', () {
    test('no request for a small gap (normal 1-min stream)', () {
      // Live at 100 min, newest stored at 95 min → 5-min gap (< 10 min min).
      expect(
        Libre3Connection.backfillStartLifeCount(100 * 60, 95 * 60),
        isNull,
      );
    });

    test('a real gap requests only the missed span', () {
      // Live at 200 min, newest stored at 140 min → 60-min gap → start at 140.
      expect(
        Libre3Connection.backfillStartLifeCount(200 * 60, 140 * 60),
        140,
      );
    });

    test('a huge gap is capped at the max window', () {
      // Live at 1000 min, newest at 100 min → 900-min gap, capped to 360 →
      // start at 1000 - 360 = 640.
      expect(
        Libre3Connection.backfillStartLifeCount(1000 * 60, 100 * 60),
        640,
      );
    });

    test('no prior history pulls the capped recent window, clamped at 0', () {
      // Live at 60 min, no prior → cap 360 but life count only 60 → clamp to 0.
      expect(Libre3Connection.backfillStartLifeCount(60 * 60, null), 0);
      // Live at 500 min, no prior → 500 - 360 = 140.
      expect(Libre3Connection.backfillStartLifeCount(500 * 60, null), 140);
    });
  });
}
