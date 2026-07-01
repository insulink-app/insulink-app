import 'package:health/health.dart';

import '../sport_models.dart';
import '../sport_state.dart';
import 'sport_activity_state.dart';

enum HealthImportResult { success, unavailable, denied }

/// Importiert Daten aus Google Health (Health Connect) über die **komplette
/// verfügbare Historie**: Schritte, Distanz und Kalorien werden tagesweise ins
/// persistente Aktivitätsarchiv gemischt (Basis der Detail-Seiten), der heutige
/// Tag speist zusätzlich die „Heute"-Kacheln, und Gewichtseinträge fließen in
/// den Verlauf. Kapselt das `health`-Plugin (Android/Health Connect).
class HealthImporter {
  final Health _health = Health();

  /// Wie weit zurück als „komplette" Historie geladen wird. `ponytail:` drei
  /// Jahre decken die üblichen Health-Connect-Retentions ab; weiter zurück nur,
  /// falls jemand tatsächlich ältere Daten hält.
  static const _historyYears = 3;

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
    // Ohne diese Berechtigung liefert Health Connect nur die letzten 30 Tage —
    // für die komplette Historie ist sie nötig (best-effort).
    if (await _health.isHealthDataHistoryAvailable() &&
        !await _health.isHealthDataHistoryAuthorized()) {
      await _health.requestHealthDataHistoryAuthorization();
    }
    final now = DateTime.now();
    final start = DateTime(now.year - _historyYears);
    final archive = await _dailyArchive(start, now);
    await activity.mergeArchive(archive);
    _applyToday(activity, archive, now);
    await sport.mergeWeights(await _weights(start, now));
    return HealthImportResult.success;
  }

  /// Heutigen Tag zusätzlich in die „Heute"-Kacheln übernehmen (überschreibt die
  /// Pedometer-Schätzung).
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

  Future<List<DailyActivity>> _dailyArchive(DateTime start, DateTime end) async {
    final steps = await _bucketSum(HealthDataType.STEPS, start, end);
    final distance = await _bucketSum(HealthDataType.DISTANCE_DELTA, start, end);
    final calories =
        await _bucketSum(HealthDataType.ACTIVE_ENERGY_BURNED, start, end);
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

  /// Summiert die numerischen Datenpunkte eines Typs je lokalem Kalendertag.
  Future<Map<String, double>> _bucketSum(
    HealthDataType type,
    DateTime start,
    DateTime end,
  ) async {
    final points = await _health.getHealthDataFromTypes(
      types: [type],
      startTime: start,
      endTime: end,
    );
    final out = <String, double>{};
    for (final point in _health.removeDuplicates(points)) {
      final value = point.value;
      if (value is NumericHealthValue) {
        final key = _dateKey(point.dateFrom.toLocal());
        out[key] = (out[key] ?? 0) + value.numericValue.toDouble();
      }
    }
    return out;
  }

  Future<List<WeightEntry>> _weights(DateTime start, DateTime end) async {
    final points = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WEIGHT],
      startTime: start,
      endTime: end,
    );
    final out = <WeightEntry>[];
    for (final point in _health.removeDuplicates(points)) {
      final value = point.value;
      if (value is NumericHealthValue) {
        out.add(WeightEntry(
          atEpochMs: point.dateFrom.millisecondsSinceEpoch,
          kg: value.numericValue.toDouble(),
        ));
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
