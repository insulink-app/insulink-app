import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'google_health_models.dart';

/// Outcome of reading Google Health metrics from Health Connect.
enum GoogleHealthImportResult { success, unavailable, denied }

/// Result of one Google Health read: per-day metrics + the most recent HR sample.
class GoogleHealthImport {
  final GoogleHealthImportResult result;
  final List<GoogleHealthDay> days;
  final int? latestHr;
  final int? latestHrAtMs;

  const GoogleHealthImport(
    this.result, {
    this.days = const [],
    this.latestHr,
    this.latestHrAtMs,
  });
}

/// Reads the Google Health-specific metrics from Google Health (Health Connect):
/// resting heart rate, sleep, blood oxygen (daily) and the latest heart rate.
/// The Google Health app syncs these into Health Connect, so this reuses the same
/// `health` plugin as HealthImporter — no BLE, no Google Health Web API. 30-day window
/// (tiles need only the latest day; leaves room for a future history chart).
class GoogleHealthImporter {
  final Health _health = Health();

  static const _historyDays = 30;

  /// Sleep-stage types, in the fixed order the accumulator buckets them by.
  static const _stageTypes = [
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_AWAKE,
  ];

  static const _types = [
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.BLOOD_OXYGEN,
    ..._stageTypes,
  ];
  static final _read = List.filled(_types.length, HealthDataAccess.READ);

  Future<GoogleHealthImport> import() async {
    await _health.configure();
    if (await _health.getHealthConnectSdkStatus() !=
        HealthConnectSdkStatus.sdkAvailable) {
      await _health.installHealthConnect();
      return const GoogleHealthImport(GoogleHealthImportResult.unavailable);
    }
    if (!await _health.requestAuthorization(_types, permissions: _read)) {
      return const GoogleHealthImport(GoogleHealthImportResult.denied);
    }
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: _historyDays));
    final resting = await _dailyLast(HealthDataType.RESTING_HEART_RATE, start, now);
    final spo2 = await _dailyLast(HealthDataType.BLOOD_OXYGEN, start, now);
    final sleep = await _sleepMinutes(start, now);
    final stages = await _sleepStages(start, now);
    final latest = await _latestHr(now.subtract(const Duration(days: 1)), now);
    return GoogleHealthImport(
      GoogleHealthImportResult.success,
      days: _mergeDays(resting, sleep, spo2, stages),
      latestHr: latest.hr,
      latestHrAtMs: latest.atMs,
    );
  }

  // Per-day last numeric value of an instantaneous type (resting HR, SpO2).
  Future<Map<String, int>> _dailyLast(
    HealthDataType type,
    DateTime start,
    DateTime end,
  ) async {
    final out = <String, int>{};
    try {
      final points = await _health.getHealthDataFromTypes(
        types: [type],
        startTime: start,
        endTime: end,
      );
      for (final point in _health.removeDuplicates(points)) {
        final value = point.value;
        if (value is NumericHealthValue) {
          out[_dateKey(point.dateFrom.toLocal())] = value.numericValue.round();
        }
      }
    } catch (_) {
      // ponytail: a type Health Connect can't serve is skipped, others still read.
    }
    return out;
  }

  // Sleep minutes per wake-day, from SLEEP_SESSION durations.
  Future<Map<String, int>> _sleepMinutes(DateTime start, DateTime end) async {
    final out = <String, int>{};
    try {
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.SLEEP_SESSION],
        startTime: start,
        endTime: end,
      );
      for (final point in points) {
        final minutes = point.dateTo.difference(point.dateFrom).inMinutes;
        if (minutes > 0) {
          out[_dateKey(point.dateTo.toLocal())] = minutes;
        }
      }
    } catch (_) {/* skip if unavailable */}
    return out;
  }

  // Sleep-stage minutes per wake-day, bucketed [deep, rem, light, awake] by the
  // record type's position in _stageTypes.
  Future<Map<String, SleepStages>> _sleepStages(
    DateTime start,
    DateTime end,
  ) async {
    final acc = <String, List<int>>{};
    try {
      final points = await _health.getHealthDataFromTypes(
        types: _stageTypes,
        startTime: start,
        endTime: end,
      );
      for (final point in points) {
        final minutes = point.dateTo.difference(point.dateFrom).inMinutes;
        final index = _stageTypes.indexOf(point.type);
        if (minutes <= 0 || index < 0) {
          continue;
        }
        final bucket = acc.putIfAbsent(
          _dateKey(point.dateTo.toLocal()),
          () => [0, 0, 0, 0],
        );
        bucket[index] += minutes;
      }
    } catch (_) {/* skip if unavailable */}
    return {
      for (final entry in acc.entries)
        entry.key: SleepStages(
          deep: entry.value[0],
          rem: entry.value[1],
          light: entry.value[2],
          awake: entry.value[3],
        ),
    };
  }

  /// Live HR poll: configures the plugin and returns the newest HEART_RATE
  /// sample from the last 15 min. Assumes permission is already granted (Google Health
  /// "connected") — Health Connect reads need only a Context, not an Activity,
  /// so this works from the foreground-service isolate.
  Future<({int? hr, int? atMs})> latestHeartRate() async {
    try {
      await _health.configure();
    } catch (error) {
      debugPrint('live-hr: configure failed: $error');
      return (hr: null, atMs: null);
    }
    final now = DateTime.now();
    return _latestHr(now.subtract(const Duration(minutes: 15)), now);
  }

  /// All HEART_RATE samples of one calendar day, ascending — the source for the
  /// intraday pulse curve. Read live (not cached): a full day of per-minute
  /// samples is large and Health Connect already keeps the history.
  Future<List<({DateTime at, int bpm})>> intradayHeartRate(DateTime day) async {
    try {
      await _health.configure();
    } catch (error) {
      debugPrint('intraday-hr: configure failed: $error');
      return const [];
    }
    final start = DateTime(day.year, day.month, day.day);
    final now = DateTime.now();
    final dayEnd = start.add(const Duration(days: 1));
    final end = dayEnd.isAfter(now) ? now : dayEnd;
    final out = <({DateTime at, int bpm})>[];
    try {
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: start,
        endTime: end,
      );
      for (final point in _health.removeDuplicates(points)) {
        final value = point.value;
        if (value is NumericHealthValue) {
          out.add((at: point.dateFrom.toLocal(), bpm: value.numericValue.round()));
        }
      }
    } catch (error) {
      debugPrint('intraday-hr: read failed: $error');
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  Future<({int? hr, int? atMs})> _latestHr(DateTime start, DateTime end) async {
    try {
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: start,
        endTime: end,
      );
      HealthDataPoint? latest;
      for (final point in points) {
        if (latest == null || point.dateFrom.isAfter(latest.dateFrom)) {
          latest = point;
        }
      }
      // ponytail: temporary diagnostic for the "no live HR" report — how many
      // HEART_RATE points Health Connect actually returns and how fresh they are.
      final age = latest == null
          ? 'none'
          : '${DateTime.now().difference(latest.dateFrom).inSeconds}s ago';
      debugPrint('live-hr: ${points.length} pts in window, newest $age');
      final value = latest?.value;
      if (value is NumericHealthValue) {
        return (
          hr: value.numericValue.round(),
          atMs: latest!.dateFrom.millisecondsSinceEpoch,
        );
      }
    } catch (error) {
      debugPrint('live-hr: read failed: $error');
    }
    return (hr: null, atMs: null);
  }

  List<GoogleHealthDay> _mergeDays(
    Map<String, int> resting,
    Map<String, int> sleep,
    Map<String, int> spo2,
    Map<String, SleepStages> stages,
  ) {
    final keys = {...resting.keys, ...sleep.keys, ...spo2.keys, ...stages.keys};
    final days = [
      for (final key in keys)
        GoogleHealthDay(
          dateKey: key,
          restingHr: resting[key],
          sleepMinutes: sleep[key],
          spo2: spo2[key],
          sleepStages: stages[key],
        ),
    ];
    days.sort((a, b) => a.dateKey.compareTo(b.dateKey));
    return days;
  }

  String _dateKey(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '${time.year}-$month-$day';
  }
}
