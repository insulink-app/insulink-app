import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/activity/health_importer.dart';

void main() {
  group('retryRead', () {
    test('returns the value once an attempt succeeds', () async {
      var calls = 0;
      final result = await retryRead<int>(
        () async {
          calls++;
          if (calls < 3) {
            throw Exception('rate limit');
          }
          return [42];
        },
        backoff: Duration.zero,
      );
      expect(result, [42]);
      expect(calls, 3);
    });

    test('returns null when every attempt throws', () async {
      var calls = 0;
      final result = await retryRead<int>(
        () async {
          calls++;
          throw Exception('rate limit');
        },
        maxAttempts: 3,
        backoff: Duration.zero,
      );
      expect(result, isNull);
      expect(calls, 3);
    });

    test('does not retry after a first-attempt success', () async {
      var calls = 0;
      final result = await retryRead<int>(
        () async {
          calls++;
          return [1, 2];
        },
        backoff: Duration.zero,
      );
      expect(result, [1, 2]);
      expect(calls, 1);
    });
  });

  group('monthlyWindows', () {
    test('splits a range into contiguous, non-overlapping months', () {
      final windows = monthlyWindows(
        DateTime(2024, 1, 15),
        DateTime(2024, 3, 10),
      );
      expect(windows, [
        (start: DateTime(2024, 1, 15), end: DateTime(2024, 2)),
        (start: DateTime(2024, 2), end: DateTime(2024, 3)),
        (start: DateTime(2024, 3), end: DateTime(2024, 3, 10)),
      ]);
    });

    test('is empty when start is not before end', () {
      expect(monthlyWindows(DateTime(2024, 5), DateTime(2024, 5)), isEmpty);
    });
  });
}
