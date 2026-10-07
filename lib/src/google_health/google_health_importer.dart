import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'google_health_models.dart';
import 'package:insulink/src/google_health/sleep_nights.dart';

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
/// resting heart rate, sleep, respiratory rate (daily) and the latest heart rate.
/// The Google Health app syncs these into Health Connect, so this reuses the same
/// `health` plugin as HealthImporter — no BLE, no Google Health Web API. 30-day window
/// (tiles need only the latest day; leaves room for a future history chart).
class GoogleHealthImporter {
  final Health _health = Health();

  static const _historyDays = 30;

  /// Sleep-stage types, in the SAME order as the [SleepStage] enum — the index
  /// into this list is the stage's enum index. Append only (see [SleepStage]).
  static const _stageTypes = [
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_AWAKE_IN_BED,
  ];

  /// Public so [HealthPermissions] can request these together with the activity
  /// types — one prompt instead of two disjoint ones.
  static const types = [
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.RESPIRATORY_RATE,
    ..._stageTypes,
  ];
  static final _read = List.filled(types.length, HealthDataAccess.READ);

  /// Reads what has ALREADY been granted — never prompts. The Sport page
  /// refreshes these on open and every 5 min, so prompting here would ambush the
  /// user; asking is [HealthPermissions]' job, from the connect button.
  Future<GoogleHealthImport> import() async {
    await _health.configure();
    if (await _health.getHealthConnectSdkStatus() !=
        HealthConnectSdkStatus.sdkAvailable) {
      return const GoogleHealthImport(GoogleHealthImportResult.unavailable);
    }
    if (await _health.hasPermissions(types, permissions: _read) != true) {
      return const GoogleHealthImport(GoogleHealthImportResult.denied);
    }
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: _historyDays));
    final resting = await _dailyLast(
      HealthDataType.RESTING_HEART_RATE,
      start,
      now,
    );
    final respiratory = await _dailyLast(
      HealthDataType.RESPIRATORY_RATE,
      start,
      now,
    );
    final sleep = await _sleepMinutes(start, now);
    final segments = await _sleepSegments(start, now);
    final latest = await _latestHr(now.subtract(const Duration(days: 1)), now);
    return GoogleHealthImport(
      GoogleHealthImportResult.success,
      days: _mergeDays(resting, sleep, respiratory, segments),
      latestHr: latest.hr,
      latestHrAtMs: latest.atMs,
    );
  }

  // Per-day last numeric value of an instantaneous type (resting HR, breaths).
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
    } catch (error) {
      // ponytail: a type Health Connect can't serve is skipped, others still read.
      debugPrint('[gh-import] ${type.name} read failed: $error');
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
    } catch (_) {
      /* skip if unavailable */
    }
    return out;
  }

  // Chronological stage segments per wake-day (keyed like the other metrics),
  // read once — the totals AND the hypnogram both derive from these.
  Future<Map<String, List<SleepSegment>>> _sleepSegments(
    DateTime start,
    DateTime end,
  ) async {
    final segments = <SleepSegment>[];
    try {
      final points = await _health.getHealthDataFromTypes(
        types: _stageTypes,
        startTime: start,
        endTime: end,
      );
      for (final point in _health.removeDuplicates(points)) {
        final index = _stageTypes.indexOf(point.type);
        if (index < 0 || !point.dateTo.isAfter(point.dateFrom)) {
          continue;
        }
        segments.add(
          SleepSegment(
            stage: SleepStage.values[index],
            startMs: point.dateFrom.millisecondsSinceEpoch,
            endMs: point.dateTo.millisecondsSinceEpoch,
          ),
        );
      }
    } catch (_) {
      /* skip if unavailable */
    }
    return _byWakeDay(segments);
  }

  /// Whole sessions keyed by the day they END on, never single segments: a
  /// night across midnight stays one night on its wake-up day. Two sessions
  /// ending on one day (a night and a nap) keep the longer one, which is the
  /// night the sleep page is about.
  Map<String, List<SleepSegment>> _byWakeDay(List<SleepSegment> segments) {
    final byDay = <String, List<SleepSegment>>{};
    for (final night in SleepNights(segments).all) {
      final key = _dateKey(DateTime.fromMillisecondsSinceEpoch(night.endMs));
      final kept = byDay[key];
      if (kept == null ||
          night.endMs - night.first.startMs > kept.endMs - kept.first.startMs) {
        byDay[key] = night;
      }
    }
    return byDay;
  }

  // Per-stage minute totals of a night, summed from its segments.
  SleepStages _stageTotals(List<SleepSegment> segments) {
    final minutes = List.filled(SleepStage.values.length, 0);
    for (final segment in segments) {
      minutes[segment.stage.index] += Duration(
        milliseconds: segment.endMs - segment.startMs,
      ).inMinutes;
    }
    return SleepStages(
      deep: minutes[SleepStage.deep.index],
      rem: minutes[SleepStage.rem.index],
      light: minutes[SleepStage.light.index],
      awake: minutes[SleepStage.awake.index],
      restless: minutes[SleepStage.restless.index],
    );
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

  /// All HEART_RATE samples in `[start, end]`, ascending — the source for the
  /// intraday pulse curve (a rolling window, so it may cross midnight). Read live
  /// (not cached): a day of per-minute samples is large and Health Connect
  /// already keeps the history. [end] is clamped to now (no future samples).
  Future<List<({DateTime at, int bpm})>> heartRateBetween(
    DateTime start,
    DateTime end,
  ) async {
    try {
      await _health.configure();
    } catch (error) {
      debugPrint('intraday-hr: configure failed: $error');
      return const [];
    }
    final now = DateTime.now();
    final clampedEnd = end.isAfter(now) ? now : end;
    final out = <({DateTime at, int bpm})>[];
    try {
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: start,
        endTime: clampedEnd,
      );
      for (final point in _health.removeDuplicates(points)) {
        final value = point.value;
        if (value is NumericHealthValue) {
          out.add((
            at: point.dateFrom.toLocal(),
            bpm: value.numericValue.round(),
          ));
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
    Map<String, int> respiratory,
    Map<String, List<SleepSegment>> segments,
  ) {
    final keys = {
      ...resting.keys,
      ...sleep.keys,
      ...respiratory.keys,
      ...segments.keys,
    };
    final days = [
      for (final key in keys)
        GoogleHealthDay(
          dateKey: key,
          restingHr: resting[key],
          sleepMinutes: sleep[key],
          respiratoryRate: respiratory[key],
          sleepStages: segments[key] == null
              ? null
              : _stageTotals(segments[key]!),
          sleepTimeline: segments[key],
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
