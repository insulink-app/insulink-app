import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/demo/demo_glucose.dart';
import 'package:insulink/src/demo/demo_glucose_range.dart';

void main() {
  test('the current value is in range at every time of day', () {
    for (var minute = 0; minute < 24 * 60; minute += 10) {
      final now = DateTime(2026, 10, 4).add(Duration(minutes: minute));
      final glucose = DemoGlucose(now: now, random: Random(2026));
      final current = glucose.readings[glucose.end]!;
      expect(current, inInclusiveRange(70, 180), reason: '$now');
    }
  });

  test('older highs are kept, so time in range is not all green', () {
    final now = DateTime(2026, 10, 4, 12);
    final glucose = DemoGlucose(now: now, random: Random(2026));
    final older = glucose.readings.entries.where(
      (entry) => entry.key.isBefore(now.subtract(DemoGlucoseRange.easeIn)),
    );
    expect(older.where((entry) => entry.value > 180), isNotEmpty);
  });

  test('a value is pulled softly into range, never past it', () {
    const range = DemoGlucoseRange();
    expect(range.keep(400), lessThan(180));
    expect(range.keep(20), greaterThan(70));
    expect(range.keep(130), 130);
  });
}
