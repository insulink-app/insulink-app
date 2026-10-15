import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/activity_mode/activity_mode.dart';
import 'package:insulink/src/sport/sport_store.dart';

/// Where the activity mode is kept, and how the one in force is worked out.
///
/// A manual choice wins and lapses after [manualFor]. Without one the mode
/// follows what the user is doing: a running routine is strength, a cardio
/// recording or a walk or ride the training detection sees going on is
/// endurance. Everything is read from storage, so the service isolate and the
/// UI reach the same answer without a message between them.
///
/// Not part of the account blob, like `pod.loop_mode`: the mode is about this
/// phone's pod and this phone's sensors.
class ActivityModeStore {
  const ActivityModeStore([this._sport = const SportStore()]);

  final SportStore _sport;

  static const _storage = FlutterSecureStorage();

  static const String keyManual = 'activity_mode_manual';
  static const String keyManualUntil = 'activity_mode_manual_until';
  static const String keyDetectedAt = 'activity_mode_detected_at';

  /// How long a manual choice holds. A forgotten strength mode keeps adding
  /// basal, so no choice may hold forever.
  static const Duration manualFor = Duration(hours: 2);

  /// How long one sighting of an ongoing training counts. Bridges the gap
  /// between two detection runs, and ends the mode by itself when detection
  /// stops running (battery saver, a dead service).
  static const Duration detectedFor = Duration(minutes: 10);

  /// A workout started longer ago than this was abandoned, not finished.
  static const Duration workoutFor = Duration(hours: 4);

  /// Picks [mode] by hand for [manualFor], or hands back to detection when null.
  Future<void> choose(ActivityMode? mode, DateTime now) async {
    if (mode == null) {
      await _storage.delete(key: keyManual);
      await _storage.delete(key: keyManualUntil);
      return;
    }
    final until = now.add(manualFor).millisecondsSinceEpoch;
    await _storage.write(key: keyManual, value: mode.name);
    await _storage.write(key: keyManualUntil, value: '$until');
  }

  /// Records whether the training detection sees a training going on.
  Future<void> markDetected(bool ongoing, DateTime now) async {
    if (!ongoing) {
      await _storage.delete(key: keyDetectedAt);
      return;
    }
    await _storage.write(
      key: keyDetectedAt,
      value: '${now.millisecondsSinceEpoch}',
    );
  }

  /// The mode in force at [now].
  Future<ActivityModeReading> current(DateTime now) async {
    return await _manual(now) ?? await _followed(now);
  }

  /// The manual choice, or null when there is none or it has lapsed.
  Future<ActivityModeReading?> _manual(DateTime now) async {
    final name = await _storage.read(key: keyManual);
    final until = await _time(keyManualUntil);
    final mode = ActivityMode.values
        .where((entry) => entry.name == name)
        .firstOrNull;
    if (mode == null || until == null || !now.isBefore(until)) {
      return null;
    }
    return ActivityModeReading(mode, ActivityModeSource.manual, until: until);
  }

  /// The mode that follows from what the user is doing.
  Future<ActivityModeReading> _followed(DateTime now) async {
    if (await _workoutRuns(now)) {
      return const ActivityModeReading(
        ActivityMode.strength,
        ActivityModeSource.workout,
      );
    }
    if (await _sport.loadActiveTraining() != null) {
      return const ActivityModeReading(
        ActivityMode.endurance,
        ActivityModeSource.recording,
      );
    }
    if (await _detectedSince(now.subtract(detectedFor))) {
      return const ActivityModeReading(
        ActivityMode.endurance,
        ActivityModeSource.detected,
      );
    }
    return ActivityModeReading.normal;
  }

  Future<bool> _workoutRuns(DateTime now) async {
    final workout = await _sport.loadActiveWorkout();
    if (workout == null) {
      return false;
    }
    final started = DateTime.fromMillisecondsSinceEpoch(workout.startedAtMs);
    return now.difference(started) < workoutFor;
  }

  Future<bool> _detectedSince(DateTime since) async {
    final seen = await _time(keyDetectedAt);
    return seen != null && seen.isAfter(since);
  }

  Future<DateTime?> _time(String key) async {
    final epochMs = int.tryParse(await _storage.read(key: key) ?? '');
    return epochMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(epochMs);
  }
}
