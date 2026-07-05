import 'package:health/health.dart';

import 'fitbit_models.dart';

/// Outcome of reading Fitbit metrics from Health Connect.
enum FitbitImportResult { success, unavailable, denied }

/// Result of one Fitbit read: per-day metrics + the most recent HR sample.
class FitbitImport {
  final FitbitImportResult result;
  final List<FitbitDay> days;
  final int? latestHr;
  final int? latestHrAtMs;

  const FitbitImport(
    this.result, {
    this.days = const [],
    this.latestHr,
    this.latestHrAtMs,
  });
}

/// Reads the Fitbit-specific metrics from Google Health (Health Connect):
/// resting heart rate, sleep, blood oxygen (daily) and the latest heart rate.
/// The Fitbit app syncs these into Health Connect, so this reuses the same
/// `health` plugin as HealthImporter — no BLE, no Fitbit Web API. 30-day window
/// (tiles need only the latest day; leaves room for a future history chart).
class FitbitImporter {
  final Health _health = Health();

  static const _historyDays = 30;

  static const _types = [
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.BLOOD_OXYGEN,
  ];
  static final _read = List.filled(_types.length, HealthDataAccess.READ);

  Future<FitbitImport> import() async {
    await _health.configure();
    if (await _health.getHealthConnectSdkStatus() !=
        HealthConnectSdkStatus.sdkAvailable) {
      await _health.installHealthConnect();
      return const FitbitImport(FitbitImportResult.unavailable);
    }
    if (!await _health.requestAuthorization(_types, permissions: _read)) {
      return const FitbitImport(FitbitImportResult.denied);
    }
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: _historyDays));
    final resting = await _dailyLast(HealthDataType.RESTING_HEART_RATE, start, now);
    final spo2 = await _dailyLast(HealthDataType.BLOOD_OXYGEN, start, now);
    final sleep = await _sleepMinutes(start, now);
    final latest = await _latestHr(now.subtract(const Duration(days: 1)), now);
    return FitbitImport(
      FitbitImportResult.success,
      days: _mergeDays(resting, sleep, spo2),
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
      final value = latest?.value;
      if (value is NumericHealthValue) {
        return (
          hr: value.numericValue.round(),
          atMs: latest!.dateFrom.millisecondsSinceEpoch,
        );
      }
    } catch (_) {/* skip if unavailable */}
    return (hr: null, atMs: null);
  }

  List<FitbitDay> _mergeDays(
    Map<String, int> resting,
    Map<String, int> sleep,
    Map<String, int> spo2,
  ) {
    final keys = {...resting.keys, ...sleep.keys, ...spo2.keys};
    final days = [
      for (final key in keys)
        FitbitDay(
          dateKey: key,
          restingHr: resting[key],
          sleepMinutes: sleep[key],
          spo2: spo2[key],
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
