import 'dart:collection';

import 'package:insulink/src/analysis/compression/night_sleep.dart';

/// A dip the filter takes for a compression low: the readings strictly
/// between [fromMinute] and [toMinute] (epoch minutes), the slope into it and
/// the peak out of it, with [nadirMgdl] at the bottom.
typedef CompressionDip = ({int fromMinute, int toMinute, int nadirMgdl});

/// Finds compression lows in the glucose archive afterwards: a low while
/// asleep that glucose climbs out of faster than a body does without food.
///
/// Lying on the sensor squeezes the tissue around it, the reading drops, and
/// it comes back as soon as the sleeper turns over. A real low at night with
/// nothing eaten recovers slowly, under about 1 mg/dL a minute. So a low counts
/// when its lowest reading lies in a [NightSleep] and glucose then rises at
/// least [_minRiseRate] mg/dL a minute, by at least [_minRise], within
/// [_lookAround], and no meal was logged around it (`docs/COMPRESSION_LOWS.md`).
///
/// Live this cannot work: the rise that gives it away comes only after the
/// low. That is why it is a filter for the analysis, never for an alarm.
class CompressionLows {
  const CompressionLows({required this.sleeps, required this.mealMinutes});

  final List<NightSleep> sleeps;

  /// Epoch minutes of the logged meals.
  final List<int> mealMinutes;

  static const _low = 70;
  static const _episodeGap = 15;
  static const _lookAround = 20;
  static const _minRise = 20;
  static const _minRiseRate = 1.5;
  static const _mealMargin = 30;

  /// Every compression dip in [archive] (epoch minute to mg/dL).
  List<CompressionDip> find(SplayTreeMap<int, int> archive) {
    final readings = archive.entries.toList();
    return [for (final nadir in _nadirs(readings)) ?_dip(readings, nadir)];
  }

  /// The index of the lowest reading of each run of readings under [_low].
  List<int> _nadirs(List<MapEntry<int, int>> readings) {
    final nadirs = <int>[];
    int? previous;
    for (var index = 0; index < readings.length; index++) {
      if (readings[index].value >= _low) {
        previous = null;
        continue;
      }
      final sameRun =
          previous != null &&
          readings[index].key - readings[previous].key <= _episodeGap;
      if (!sameRun) {
        nadirs.add(index);
      } else if (readings[index].value < readings[nadirs.last].value) {
        nadirs.last = index;
      }
      previous = index;
    }
    return nadirs;
  }

  /// The dip around the reading at [nadirIndex], or null when it is no
  /// compression.
  CompressionDip? _dip(List<MapEntry<int, int>> readings, int nadirIndex) {
    final nadir = readings[nadirIndex];
    final before = _peak(readings, nadirIndex, -1);
    final after = _peak(readings, nadirIndex, 1);
    if (before == null || after == null || !_asleep(nadir.key)) {
      return null;
    }
    final rise = after.value - nadir.value;
    final rate = rise / (after.key - nadir.key);
    if (rise < _minRise || rate < _minRiseRate || _mealNear(before, after)) {
      return null;
    }
    return (
      fromMinute: before.key,
      toMinute: after.key,
      nadirMgdl: nadir.value,
    );
  }

  /// The highest reading within [_lookAround] minutes of the one at
  /// [nadirIndex], walking in [direction] (-1 back, 1 ahead), or null when
  /// there is none.
  MapEntry<int, int>? _peak(
    List<MapEntry<int, int>> readings,
    int nadirIndex,
    int direction,
  ) {
    MapEntry<int, int>? peak;
    final nadirMinute = readings[nadirIndex].key;
    for (
      var index = nadirIndex + direction;
      index >= 0 &&
          index < readings.length &&
          (readings[index].key - nadirMinute).abs() <= _lookAround;
      index += direction
    ) {
      if (peak == null || readings[index].value > peak.value) {
        peak = readings[index];
      }
    }
    return peak;
  }

  bool _asleep(int epochMinute) {
    final at = DateTime.fromMillisecondsSinceEpoch(epochMinute * 60000);
    return sleeps.any((sleep) => sleep.contains(at));
  }

  bool _mealNear(MapEntry<int, int> before, MapEntry<int, int> after) {
    return mealMinutes.any(
      (minute) => minute >= before.key - _mealMargin && minute <= after.key,
    );
  }
}
