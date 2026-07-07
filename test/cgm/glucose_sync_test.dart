import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/glucose_sync.dart';

void main() {
  test('chunk splits a 282-entry map preserving every key/value', () {
    final values = {
      for (var minute = 0; minute < 282; minute++) minute: 100 + minute,
    };
    final chunks = GlucoseSync.chunk(values, 60);
    expect(chunks.length, 5); // ceil(282 / 60)
    expect(chunks.map((part) => part.length).toList(), [60, 60, 60, 60, 42]);
    final merged = <int, int>{};
    for (final part in chunks) {
      merged.addAll(part);
    }
    expect(merged, values);
  });

  test('chunk of an empty map is empty', () {
    expect(GlucoseSync.chunk({}, 60), isEmpty);
  });

  test('nextBackoff doubles then caps at 300s', () {
    var backoff = const Duration(seconds: 30);
    final sequence = <int>[];
    for (var step = 0; step < 6; step++) {
      sequence.add(backoff.inSeconds);
      backoff = GlucoseSync.nextBackoff(backoff);
    }
    expect(sequence, [30, 60, 120, 240, 300, 300]);
  });
}
