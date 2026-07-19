import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/libre3/libre3_connection.dart';
import 'package:insulink/src/libre3/libre3_transport.dart';

void main() {
  group('Libre3Transport.historicBoundary', () {
    test('snaps to a 5-min boundary with Juggluco\'s 16-count margin', () {
      // ((18651 - 16) / 5) * 5 = (18635 / 5) * 5 = 18635.
      expect(Libre3Transport.historicBoundary(18651), 18635);
      // ((18657 - 16) / 5) * 5 = (18641 / 5) * 5 = 18640.
      expect(Libre3Transport.historicBoundary(18657), 18640);
    });

    test('never goes negative for a young sensor', () {
      expect(Libre3Transport.historicBoundary(10), 0);
      expect(Libre3Transport.historicBoundary(0), 0);
    });
  });

  // liveSecs is seconds-since-start; life count = liveSecs / 60.
  group('Libre3Connection.backfillStartLifeCount', () {
    test('no request for a small gap (normal 1-min stream)', () {
      // Live at 100 min, newest stored at 99 min → 1-min gap, below the
      // min-gap threshold (no catch-up for the normal 1-min stream).
      expect(
        Libre3Connection.backfillStartLifeCount(100 * 60, 99 * 60),
        isNull,
      );
    });

    test('a real gap requests only the missed span', () {
      // Live at 200 min, newest stored at 140 min → 60-min gap → start at 140.
      expect(Libre3Connection.backfillStartLifeCount(200 * 60, 140 * 60), 140);
    });

    test('a huge gap is capped at the max window', () {
      // Live at 1000 min, newest at 100 min → 900-min gap, capped to 360 →
      // start at 1000 - 360 = 640.
      expect(Libre3Connection.backfillStartLifeCount(1000 * 60, 100 * 60), 640);
    });

    test('no prior history pulls the capped recent window, clamped at 0', () {
      // Live at 60 min, no prior → cap 360 but life count only 60 → clamp to 0.
      expect(Libre3Connection.backfillStartLifeCount(60 * 60, null), 0);
      // Live at 500 min, no prior → 500 - 360 = 140.
      expect(Libre3Connection.backfillStartLifeCount(500 * 60, null), 140);
    });
  });
}
