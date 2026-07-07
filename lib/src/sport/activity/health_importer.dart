import 'package:health/health.dart';

import '../sport_models.dart';
import '../sport_state.dart';
import 'sport_activity_state.dart';

/// Outcome of a Health import.
enum HealthImportResult { success, unavailable, denied }

/// Imports the last [_historyDays] of data from Google Health (Health Connect):
/// steps, distance and calories are merged day-by-day into the persistent
/// activity archive (the basis of the detail pages), today additionally feeds the
/// "Today" tiles, and weight entries flow into the history. Wraps the `health`
/// plugin (Android/Health Connect), mirroring [GoogleHealthImporter].
///
/// Steps/distance/calories are read via Health Connect's AGGREGATION API (daily
/// buckets) rather than raw records: it de-duplicates across source apps and is
/// far less likely to hit read rate-limits than summing thousands of raw points.
class HealthImporter {
  final Health _health = Health();

  /// How far back to import. 90 days needs the "read past data" permission
  /// (anything older than 30 days does).
  static const _historyDays = 90;

  /// One day, in seconds — the aggregation bucket size.
  static const _dayInterval = 86400;

  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WEIGHT,
  ];
  static final _read = List.filled(_types.length, HealthDataAccess.READ);

  Future<HealthImportResult> import(
    SportState sport,
    SportActivityState activity,
  ) async {
    await _health.configure();
    if (await _health.getHealthConnectSdkStatus() !=
        HealthConnectSdkStatus.sdkAvailable) {
      await _health.installHealthConnect();
      return HealthImportResult.unavailable;
    }
    if (!await _health.requestAuthorization(_types, permissions: _read)) {
      return HealthImportResult.denied;
    }
    await _ensureHistoryAccess();
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: _historyDays));
    final archive = await _dailyArchive(start, now);
    await activity.mergeArchive(archive);
    _applyToday(activity, archive, now);
    await sport.mergeWeights(await _weights(start, now));
    return HealthImportResult.success;
  }

  /// Requests the "read past data" permission (needed for anything older than 30
  /// days). Best-effort: if it isn't granted, older reads simply return nothing.
  Future<void> _ensureHistoryAccess() async {
    if (await _health.isHealthDataHistoryAvailable() &&
        !await _health.isHealthDataHistoryAuthorized()) {
      await _health.requestHealthDataHistoryAuthorization();
    }
  }

  /// Also apply today to the "Today" tiles (overrides the pedometer estimate).
  void _applyToday(
    SportActivityState activity,
    List<DailyActivity> archive,
    DateTime now,
  ) {
    final today = _dateKey(now);
    for (final day in archive) {
      if (day.dateKey == today) {
        activity.setImported(
          steps: day.steps,
          distanceKm: day.distanceKm,
          calories: day.calories,
        );
        return;
      }
    }
  }

  Future<List<DailyActivity>> _dailyArchive(
    DateTime start,
    DateTime end,
  ) async {
    final steps = await _dailyTotals(HealthDataType.STEPS, start, end);
    final distance = await _dailyTotals(
      HealthDataType.DISTANCE_DELTA,
      start,
      end,
    );
    final calories = await _dailyTotals(
      HealthDataType.ACTIVE_ENERGY_BURNED,
      start,
      end,
    );
    final keys = {...steps.keys, ...distance.keys, ...calories.keys};
    return [
      for (final key in keys)
        DailyActivity(
          dateKey: key,
          steps: (steps[key] ?? 0).round(),
          distanceKm: (distance[key] ?? 0) / 1000,
          calories: calories[key] ?? 0,
        ),
    ];
  }

  /// Daily totals of an aggregatable type across the range, via Health Connect's
  /// aggregation (one bucket per day). Distance comes back in metres, energy in
  /// kilocalories.
  Future<Map<String, double>> _dailyTotals(
    HealthDataType type,
    DateTime start,
    DateTime end,
  ) async {
    final out = <String, double>{};
    try {
      final points = await _health.getHealthIntervalDataFromTypes(
        startDate: start,
        endDate: end,
        types: [type],
        interval: _dayInterval,
      );
      for (final point in points) {
        final value = point.value;
        if (value is NumericHealthValue) {
          final total = value.numericValue.toDouble();
          // Aggregation emits a bucket for EVERY day, including empty ones
          // (value 0). Skip those, so the archive never fills with zero-days.
          if (total <= 0) {
            continue;
          }
          final key = _dateKey(point.dateFrom.toLocal());
          out[key] = (out[key] ?? 0) + total;
        }
      }
    } catch (_) {
      // ponytail: a range Health Connect can't serve (e.g. history permission
      // missing for >30 days) is skipped; grant it and re-import for the rest.
    }
    return out;
  }

  Future<List<WeightEntry>> _weights(DateTime start, DateTime end) async {
    try {
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: start,
        endTime: end,
      );
      return [
        for (final point in _health.removeDuplicates(points))
          if (point.value case final NumericHealthValue value)
            WeightEntry(
              atEpochMs: point.dateFrom.millisecondsSinceEpoch,
              kg: value.numericValue.toDouble(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  String _dateKey(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '${time.year}-$month-$day';
  }
}
