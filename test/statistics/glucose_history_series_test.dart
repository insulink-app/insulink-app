import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/statistics/history/glucose_history_series.dart';

/// mg/dL glucose state (no conversion) so y == input mean.
ProfileGlucoseState _mgdl() => ProfileGlucoseState(
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
  test('picks bucket granularity from the span', () {
    final empty = SplayTreeMap<int, int>();
    expect(
      GlucoseHistorySeries(empty, const Duration(days: 1), _mgdl()).bucket,
      HistoryBucket.hour,
    );
    expect(
      GlucoseHistorySeries(empty, const Duration(days: 7), _mgdl()).bucket,
      HistoryBucket.weekday,
    );
    expect(
      GlucoseHistorySeries(empty, const Duration(days: 30), _mgdl()).bucket,
      HistoryBucket.monthDay,
    );
    expect(
      GlucoseHistorySeries(empty, const Duration(days: 365), _mgdl()).bucket,
      HistoryBucket.month,
    );
  });

  test('averages readings within an hour bucket and fills the span', () {
    final base = DateTime(2026, 6, 1, 8); // local 08:00
    final archive = SplayTreeMap<int, int>.from({
      _min(base): 100,
      _min(base.add(const Duration(minutes: 15))): 140, // same hour → mean 120
      _min(base.add(const Duration(hours: 2))): 90, // 10:00, gap at 09:00
    });
    final series = GlucoseHistorySeries(
      archive,
      const Duration(days: 1),
      _mgdl(),
    );
    final spots = series.build();

    expect(series.starts.length, 3); // 08, 09, 10 inclusive
    expect(series.starts.first.hour, 8);
    expect(spots.map((spot) => spot.x), [0, 2]); // 09:00 empty → no spot
    expect(spots.first.y, 120);
    expect(spots.last.y, 90);
  });
}
