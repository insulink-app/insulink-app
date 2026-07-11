import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One heart-rate sample: a wall-clock time and a bpm.
typedef PulseSample = ({DateTime at, int bpm});

/// Granular intraday pulse archive — the raw material to redraw the heart-rate
/// curve entirely from our own storage (and backend), without Health Connect.
/// Samples are bucketed to one averaged point per minute and kept per local day
/// under a key each, so a live append rewrites only today's blob. An index key
/// tracks the stored days and prunes to the most recent [_keepDays].
class IntradayPulseStore {
  static const _prefix = 'gh.pulse.';
  static const _indexKey = 'gh.pulse.index';
  static const _keepDays = 90;
  static const _storage = FlutterSecureStorage();

  const IntradayPulseStore();

  /// Merges samples into the per-day archive (one averaged point per minute),
  /// returning the day keys it touched so the caller can sync just those.
  Future<Set<String>> merge(Iterable<PulseSample> samples) async {
    final byDay = <String, List<PulseSample>>{};
    for (final sample in samples) {
      final local = sample.at.toLocal();
      byDay.putIfAbsent(_dayKey(local), () => []).add((
        at: local,
        bpm: sample.bpm,
      ));
    }
    for (final entry in byDay.entries) {
      final buckets = await _readBuckets(entry.key)
        ..addAll(bucketByMinute(entry.value));
      await _writeBuckets(entry.key, buckets);
    }
    await _touchIndex(byDay.keys);
    return byDay.keys.toSet();
  }

  /// Averages the samples that fall in each minute into a single bpm, keyed by
  /// minute-since-epoch (the wire + storage key for a point).
  @visibleForTesting
  Map<int, int> bucketByMinute(Iterable<PulseSample> samples) {
    final sums = <int, ({int total, int count})>{};
    for (final sample in samples) {
      final minute = _minute(sample.at);
      final current = sums[minute];
      sums[minute] = current == null
          ? (total: sample.bpm, count: 1)
          : (total: current.total + sample.bpm, count: current.count + 1);
    }
    return {
      for (final entry in sums.entries)
        entry.key: (entry.value.total / entry.value.count).round(),
    };
  }

  /// Ascending samples stored in `[from, to]`, spanning day boundaries — the
  /// rolling 24 h chart window (which crosses midnight) reads through this.
  Future<List<PulseSample>> rangeCurve(DateTime from, DateTime to) async {
    final days = <String>{};
    var cursor = DateTime(from.year, from.month, from.day);
    while (!cursor.isAfter(to)) {
      days.add(_dayKey(cursor));
      cursor = cursor.add(const Duration(days: 1));
    }
    final all = await samplesForDays(days);
    return [
      for (final sample in all)
        if (!sample.at.isBefore(from) && !sample.at.isAfter(to)) sample,
    ]..sort((a, b) => a.at.compareTo(b.at));
  }

  /// Every stored sample across the given day keys (ascending per day), the
  /// canonical minute buckets — used to push a day's curve to the backend.
  Future<List<PulseSample>> samplesForDays(Iterable<String> dayKeys) async {
    final out = <PulseSample>[];
    for (final key in dayKeys) {
      final buckets = await _readBuckets(key);
      final minutes = buckets.keys.toList()..sort();
      for (final minute in minutes) {
        out.add((
          at: DateTime.fromMillisecondsSinceEpoch(minute * 60000),
          bpm: buckets[minute]!,
        ));
      }
    }
    return out;
  }

  Future<Map<int, int>> _readBuckets(String dayKey) async {
    final raw = await _storage.read(key: '$_prefix$dayKey');
    if (raw == null) {
      return {};
    }
    return {
      for (final pair in jsonDecode(raw) as List)
        (pair as List)[0] as int: pair[1] as int,
    };
  }

  Future<void> _writeBuckets(String dayKey, Map<int, int> buckets) async {
    final minutes = buckets.keys.toList()..sort();
    await _storage.write(
      key: '$_prefix$dayKey',
      value: jsonEncode([
        for (final minute in minutes) [minute, buckets[minute]],
      ]),
    );
  }

  /// Records the touched days in the index and prunes storage to [_keepDays].
  Future<void> _touchIndex(Iterable<String> days) async {
    final known = {...await _index(), ...days}.toList()..sort();
    final kept = known.length > _keepDays
        ? known.sublist(known.length - _keepDays)
        : known;
    for (final stale in known.where((day) => !kept.contains(day))) {
      await _storage.delete(key: '$_prefix$stale');
    }
    await _storage.write(key: _indexKey, value: jsonEncode(kept));
  }

  Future<List<String>> _index() async {
    final raw = await _storage.read(key: _indexKey);
    return raw == null ? [] : (jsonDecode(raw) as List).cast<String>();
  }

  String _dayKey(DateTime day) =>
      '${day.year}-${_two(day.month)}-${_two(day.day)}';
  String _two(int value) => value.toString().padLeft(2, '0');
  int _minute(DateTime at) => at.millisecondsSinceEpoch ~/ 60000;
}
