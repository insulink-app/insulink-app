import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/analysis/compression/compression_chart_view.dart';
import 'package:insulink/src/analysis/compression/compression_lows.dart';

/// The chart draws the series without the dip, and keeps the dip's raw
/// readings, tops included, to mark where it was.
void main() {
  final start = DateTime(2026, 10, 28, 3);
  final startMinute = start.millisecondsSinceEpoch ~/ 60000;

  /// Readings every five minutes from the session start, keyed in seconds.
  final series = SplayTreeMap.of({
    for (final (index, mgdl) in [94, 94, 66, 50, 59, 75, 95, 96].indexed)
      index * 300: mgdl,
  });
  final CompressionDip dip = (
    fromMinute: startMinute + 5,
    toMinute: startMinute + 30,
    nadirMgdl: 50,
  );

  test('the dip leaves the series and is kept to be marked', () {
    final view = CompressionChartView.of(
      series,
      sensorStart: start,
      dips: [dip],
    );

    expect(view.series.values, [94, 94, 95, 96]);
    expect(view.hidden.single.map((reading) => reading.value), [
      94,
      66,
      50,
      59,
      75,
      95,
    ]);
  });

  test('without a session clock nothing is left out', () {
    final view = CompressionChartView.of(
      series,
      sensorStart: null,
      dips: [dip],
    );

    expect(view.series, same(series));
    expect(view.hidden, isEmpty);
  });
}
