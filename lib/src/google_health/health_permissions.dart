import 'package:health/health.dart';
import 'package:insulink/src/google_health/google_health_importer.dart';
import 'package:insulink/src/sport/activity/health_importer.dart';

/// The ONE place that asks the user for Health Connect access: the union of what
/// [GoogleHealthImporter] reads (pulse, sleep, SpO2, respiratory rate) and what
/// [HealthImporter] reads (steps, distance, calories, weight), plus the "read
/// past data" grant everything older than 30 days needs.
///
/// Only user-initiated flows call this — connecting Google Health under
/// Connections, or tapping the manual import. The importers themselves never
/// prompt; they check `hasPermissions` and skip. Otherwise merely opening the
/// Sport page pops dialogs the user never asked for — and TWO of them, because
/// the two importers request disjoint type sets.
class HealthPermissions {
  final Health _health = Health();

  static final _types = <HealthDataType>{
    ...GoogleHealthImporter.types,
    ...HealthImporter.types,
  }.toList();
  static final _read = List.filled(_types.length, HealthDataAccess.READ);

  /// Prompts for everything in one pass. Deliberately returns nothing: the
  /// caller runs its own import afterwards, which reports `unavailable`/`denied`
  /// from its own checks — so the outcome stays in one place.
  Future<void> request() async {
    await _health.configure();
    if (await _health.getHealthConnectSdkStatus() !=
        HealthConnectSdkStatus.sdkAvailable) {
      await _health.installHealthConnect();
      return;
    }
    if (!await _health.requestAuthorization(_types, permissions: _read)) {
      return;
    }
    await _requestHistoryAccess();
  }

  /// The "read past data" grant. Best-effort: without it the older reads simply
  /// return nothing.
  Future<void> _requestHistoryAccess() async {
    if (await _health.isHealthDataHistoryAvailable() &&
        !await _health.isHealthDataHistoryAuthorized()) {
      await _health.requestHealthDataHistoryAuthorization();
    }
  }
}
