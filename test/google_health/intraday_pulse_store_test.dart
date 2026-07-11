import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/google_health/intraday_pulse_store.dart';

void main() {
  const store = IntradayPulseStore();

  test(
    'bucketByMinute averages samples sharing a minute, keyed by minute-epoch',
    () {
      final minute = DateTime(2026, 7, 9, 16, 4);
      final next = DateTime(2026, 7, 9, 16, 5);
      final buckets = store.bucketByMinute([
        (at: minute.add(const Duration(seconds: 2)), bpm: 60),
        (at: minute.add(const Duration(seconds: 40)), bpm: 70),
        (at: next.add(const Duration(seconds: 10)), bpm: 90),
      ]);

      final minuteKey = minute.millisecondsSinceEpoch ~/ 60000;
      final nextKey = next.millisecondsSinceEpoch ~/ 60000;
      expect(buckets[minuteKey], 65);
      expect(buckets[nextKey], 90);
      expect(buckets.length, 2);
    },
  );
}
