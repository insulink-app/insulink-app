import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/analysis/calendar/daily_time_in_range.dart';

ProfileGlucoseState _state() => ProfileGlucoseState(
  unit: GlucoseUnit.mgdl,
  targetLow: 70,
  targetHigh: 180,
  urgentLow: 55,
  low: 70,
  high: 180,
  urgentHigh: 250,
);

int _min(DateTime time) => time.millisecondsSinceEpoch ~/ 60000;

void main() {
  test('computes per-day in-range fraction, bucketed by local day', () {
    final day1 = DateTime(2026, 6, 1, 10);
    final day2 = DateTime(2026, 6, 2, 10);
    final archive = SplayTreeMap<int, int>.from({
      _min(day1): 100, // in range
      _min(day1.add(const Duration(hours: 1))): 100, // in range
      _min(day1.add(const Duration(hours: 2))): 300, // high → 2/3 in range
      _min(day2): 300, // out of range → 0/1
    });

    final tir = DailyTimeInRange(archive, _state()).build();

    expect(tir[DateTime(2026, 6, 1)], closeTo(2 / 3, 1e-9));
    expect(tir[DateTime(2026, 6, 2)], 0.0);
    expect(tir.length, 2);
  });
}
