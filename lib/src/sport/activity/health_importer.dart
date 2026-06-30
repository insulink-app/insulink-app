import 'package:health/health.dart';

import '../sport_models.dart';
import '../sport_state.dart';
import 'sport_activity_state.dart';

enum HealthImportResult { success, unavailable, denied }

/// Importiert Daten aus Google Health (Health Connect): heutige Schritte,
/// Distanz und Kalorien fließen in die „Heute"-Kacheln, Gewichtseinträge werden
/// in den Verlauf gemischt. Kapselt das `health`-Plugin (Android/Health Connect).
class HealthImporter {
  final Health _health = Health();

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
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    activity.setImported(
      steps: await _health.getTotalStepsInInterval(dayStart, now),
      distanceKm: await _sum(HealthDataType.DISTANCE_DELTA, dayStart, now) / 1000,
      calories: await _sum(HealthDataType.ACTIVE_ENERGY_BURNED, dayStart, now),
    );
    await sport.mergeWeights(await _weights(now));
    return HealthImportResult.success;
  }

  Future<double> _sum(HealthDataType type, DateTime start, DateTime end) async {
    final points = await _health.getHealthDataFromTypes(
      types: [type],
      startTime: start,
      endTime: end,
    );
    var total = 0.0;
    for (final point in _health.removeDuplicates(points)) {
      final value = point.value;
      if (value is NumericHealthValue) {
        total += value.numericValue.toDouble();
      }
    }
    return total;
  }

  Future<List<WeightEntry>> _weights(DateTime now) async {
    final points = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WEIGHT],
      startTime: now.subtract(const Duration(days: 365)),
      endTime: now,
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
}
