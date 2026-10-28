import 'dart:collection';

import 'package:insulink/src/analysis/compression/compression_lows.dart';

/// A chart series (seconds since the session start to mg/dL) with its
/// compression lows taken out: [series] is what the glucose line draws, and
/// each of [hidden] is one left-out dip, its raw readings from the top before
/// the fall to the top after the rise. The chart marks those stretches instead
/// of dropping them silently, so a gap never reads as a sensor outage.
class CompressionChartView {
  const CompressionChartView._(this.series, this.hidden, this.startSeconds);

  /// Splits [bySeconds] along [dips]. Without a [sensorStart] its keys name no
  /// time, so nothing is left out.
  factory CompressionChartView.of(
    SplayTreeMap<int, int> bySeconds, {
    required DateTime? sensorStart,
    required List<CompressionDip> dips,
  }) {
    final startSeconds = sensorStart == null
        ? null
        : sensorStart.millisecondsSinceEpoch ~/ 1000;
    final raw = CompressionChartView._(bySeconds, const [], startSeconds);
    if (startSeconds == null || dips.isEmpty || bySeconds.isEmpty) {
      return raw;
    }
    return CompressionChartView._(raw._shown(dips), [
      for (final dip in dips) ?raw._stretch(dip),
    ], startSeconds);
  }

  final SplayTreeMap<int, int> series;
  final List<List<MapEntry<int, int>>> hidden;

  /// The session start in epoch seconds, null without one.
  final int? startSeconds;

  /// The epoch minute a key of the series stands for.
  int epochMinute(int seconds) => (seconds + startSeconds!) ~/ 60;

  SplayTreeMap<int, int> _shown(List<CompressionDip> dips) {
    return SplayTreeMap.of({
      for (final entry in series.entries)
        if (!dips.any((dip) => dip.hides(epochMinute(entry.key))))
          entry.key: entry.value,
    });
  }

  /// The raw readings of [dip] with its two tops, or null when the series holds
  /// none of the left-out ones (the dip lies outside it).
  List<MapEntry<int, int>>? _stretch(CompressionDip dip) {
    final stretch = [
      for (final entry in series.entries)
        if (epochMinute(entry.key) >= dip.fromMinute &&
            epochMinute(entry.key) <= dip.toMinute)
          entry,
    ];
    final hidesAny = stretch.any((entry) => dip.hides(epochMinute(entry.key)));
    return hidesAny ? stretch : null;
  }
}
