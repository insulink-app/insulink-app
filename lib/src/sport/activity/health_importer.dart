import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../sport_models.dart';
import '../sport_state.dart';
import 'sport_activity_state.dart';

/// Outcome of a Health import. [successNoHistory] means data was imported but the
/// "read past data" permission is missing, so only ~30 days were reachable — the
/// user needs to grant it in Health Connect for the full history. [partial] means
/// some windows still failed after retries (usually Health Connect read
/// rate-limiting), so the history has gaps — the user should import again.
enum HealthImportResult { success, successNoHistory, partial, unavailable, denied }

/// Runs [read], retrying up to [maxAttempts] times with a growing [backoff]
/// between attempts. Returns the result of the first successful attempt, or null
/// if every attempt threw. Health Connect throws a `PlatformException` when its
/// burst read quota is exceeded; retrying after a short backoff recovers the
/// window instead of losing it — the reason older months used to vanish silently.
@visibleForTesting
Future<List<T>?> retryRead<T>(
  Future<List<T>> Function() read, {
  int maxAttempts = 3,
  Duration backoff = const Duration(milliseconds: 400),
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (attempt > 0) {
      await Future.delayed(backoff * attempt);
    }
    try {
      return await read();
    } catch (_) {
      // Retry after backoff on the next iteration; give up after maxAttempts.
    }
  }
  return null;
}

/// Splits `[start, end)` into contiguous, non-overlapping monthly windows.
/// `ponytail:` reading one window at a time keeps each Health Connect call small
/// AND makes the import resilient: a window Health Connect can't serve (older
/// than the granted history) fails on its own and is skipped, instead of aborting
/// the whole range. A single multi-year query would lose everything the moment
/// any part of it is inaccessible.
List<({DateTime start, DateTime end})> monthlyWindows(
  DateTime start,
  DateTime end,
) {
  final windows = <({DateTime start, DateTime end})>[];
  var windowStart = start;
  while (windowStart.isBefore(end)) {
    final nextMonth = DateTime(windowStart.year, windowStart.month + 1);
    final windowEnd = nextMonth.isBefore(end) ? nextMonth : end;
    windows.add((start: windowStart, end: windowEnd));
    windowStart = windowEnd;
  }
  return windows;
}

/// Imports data from Google Health (Health Connect) over the **entire available
/// history**: steps, distance and calories are merged day-by-day into the
/// persistent activity archive (the basis of the detail pages), today
/// additionally feeds the "Today" tiles, and weight entries flow into the
/// history. Wraps the `health` plugin (Android/Health Connect).
///
/// Steps/distance/calories are read via Health Connect's AGGREGATION API (daily
/// buckets) rather than raw records: it is the path Google recommends for long
/// ranges — it de-duplicates across source apps and is far less likely to hit
/// read rate-limits than summing thousands of raw points in Dart.
class HealthImporter {
  final Health _health = Health();

  /// How far back the "entire" history reaches. The real limit is almost always
  /// what Health Connect actually holds + the "read past data" permission, not
  /// this window (Health Connect is a relay — it only has what source apps wrote
  /// into it; old Google Fit data that never synced there cannot be read).
  static const _historyYears = 5;

  /// One day, in seconds — the aggregation bucket size.
  static const _dayInterval = 86400;

  /// Gap left after each successful window read to keep the ~240-call import from
  /// bursting straight through Health Connect's read quota. ponytail: this is a
  /// hard floor on import time (~20 s for a full 5-year history); raise
  /// [retryRead]'s backoff instead of dropping the throttle if bursts still fail.
  static const _throttle = Duration(milliseconds: 80);

  /// Windows that still failed after all retries this import — makes [import]
  /// report [HealthImportResult.partial] instead of a false success.
  int _failedWindows = 0;

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
    _failedWindows = 0;
    final history = await _ensureHistoryAccess();
    final now = DateTime.now();
    final start = DateTime(now.year - _historyYears);
    final archive = await _dailyArchive(start, now);
    await activity.mergeArchive(archive);
    _applyToday(activity, archive, now);
    await sport.mergeWeights(await _weights(start, now));
    _logImport(archive);
    if (!history) {
      return HealthImportResult.successNoHistory;
    }
    return _failedWindows > 0
        ? HealthImportResult.partial
        : HealthImportResult.success;
  }

  /// One-line diagnostic: the actual imported date range + how many windows were
  /// dropped after retries. A genuine "Health Connect never stored that old data"
  /// situation shows here as a short range with zero drops (no app can retrieve
  /// data Health Connect doesn't hold); rate-limit gaps show a non-zero drop count.
  void _logImport(List<DailyActivity> archive) {
    final keys = archive.map((day) => day.dateKey).toList()..sort();
    final range = keys.isEmpty ? 'none' : '${keys.first}..${keys.last}';
    debugPrint(
      'HealthImporter: imported ${archive.length} day(s) ($range), '
      '$_failedWindows window(s) dropped after retries',
    );
  }

  /// Reads one window with retry/backoff and the inter-window throttle. Returns
  /// null when the window still failed after all retries (counted in
  /// [_failedWindows]), so the caller skips it and the rest of the range imports.
  Future<List<T>?> _readWindow<T>(Future<List<T>> Function() read) async {
    final result = await retryRead(read);
    if (result == null) {
      _failedWindows++;
      return null;
    }
    await Future.delayed(_throttle);
    return result;
  }

  /// Requests the "read past data" (history) permission needed for anything older
  /// than 30 days, and returns whether it is (now) granted. Health Connect
  /// REVOKES it on reinstall and resets the window to 30 days before the new
  /// grant, so it must be re-requested on each fresh install — this is the usual
  /// reason a reinstalled app suddenly only sees recent data.
  ///
  /// Returns false when the permission is missing OR the feature isn't available
  /// on this device's Health Connect version — in BOTH cases only ~30 days are
  /// reachable, so the caller warns the user rather than silently importing a
  /// partial history. Uses the request's own grant result (not an immediate
  /// re-check, which races the permission callback).
  Future<bool> _ensureHistoryAccess() async {
    if (!await _health.isHealthDataHistoryAvailable()) {
      return false;
    }
    if (await _health.isHealthDataHistoryAuthorized()) {
      return true;
    }
    return _health.requestHealthDataHistoryAuthorization();
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
  /// kilocalories. Each monthly window is read independently and a failing one
  /// (e.g. older than the granted history) is skipped so the rest still imports.
  Future<Map<String, double>> _dailyTotals(
    HealthDataType type,
    DateTime start,
    DateTime end,
  ) async {
    final out = <String, double>{};
    for (final window in monthlyWindows(start, end)) {
      final points = await _readWindow(
        () => _health.getHealthIntervalDataFromTypes(
          startDate: window.start,
          endDate: window.end,
          types: [type],
          interval: _dayInterval,
        ),
      );
      if (points == null) {
        continue;
      }
      for (final point in points) {
        final value = point.value;
        if (value is NumericHealthValue) {
          final total = value.numericValue.toDouble();
          // Aggregation emits a bucket for EVERY day in the range, including
          // empty ones (value 0). Skip those, or the archive fills with
          // thousands of meaningless zero-days that blow up the backend sync.
          if (total <= 0) {
            continue;
          }
          final key = _dateKey(point.dateFrom.toLocal());
          out[key] = (out[key] ?? 0) + total;
        }
      }
    }
    return out;
  }

  Future<List<WeightEntry>> _weights(DateTime start, DateTime end) async {
    final out = <WeightEntry>[];
    for (final window in monthlyWindows(start, end)) {
      final points = await _readWindow(
        () => _health.getHealthDataFromTypes(
          types: [HealthDataType.WEIGHT],
          startTime: window.start,
          endTime: window.end,
        ),
      );
      if (points == null) {
        continue;
      }
      for (final point in _health.removeDuplicates(points)) {
        final value = point.value;
        if (value is NumericHealthValue) {
          out.add(
            WeightEntry(
              atEpochMs: point.dateFrom.millisecondsSinceEpoch,
              kg: value.numericValue.toDouble(),
            ),
          );
        }
      }
    }
    return out;
  }

  String _dateKey(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '${time.year}-$month-$day';
  }
}
