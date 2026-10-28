import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/activity_mode/activity_mode_settings.dart';

/// The endurance bouts the activity mode saw, and the recovery after them.
///
/// Booked from every endurance reading, whatever its source (a detected walk,
/// a recording, the pulse, a hand choice), so the recovery follows the
/// activity itself rather than one way of noticing it. Readings less than
/// [gap] apart belong to one bout. Only a bout of at least [minLength] earns a
/// recovery: ten minutes to the bus stop is not what drains glycogen. The
/// smaller meal bolus asks for a longer bout still
/// ([ActivityModeSettings.recoveryBolusMinutes]), since it changes a dose the
/// user gives by hand.
///
/// Each bar remembers the end of the latest bout that reached it, not just the
/// latest bout: a short walk after a long one must not take the long one's
/// recovery away.
class ActivityBout {
  const ActivityBout();

  static const _storage = FlutterSecureStorage();
  static const keyStartedAt = 'activity_bout_started_at';
  static const keyLastAt = 'activity_bout_last_at';
  static const keyRecoveryFrom = 'activity_bout_recovery_from';
  static const keyBolusFrom = 'activity_bout_bolus_from';
  static const gap = Duration(minutes: 15);
  static const minLength = Duration(minutes: 20);

  Future<void> sawEndurance(DateTime now) async {
    final last = await _time(keyLastAt);
    if (last == null || now.difference(last) > gap) {
      await _write(keyStartedAt, now);
    }
    await _write(keyLastAt, now);
    await _bookReachedLengths(now);
  }

  /// When the recovery after the last bout of [minLength] ends, or null when
  /// none applies.
  Future<DateTime?> recoveryUntil(DateTime now) => _until(keyRecoveryFrom, now);

  /// When the smaller meal bolus after the last long bout ends, or null when
  /// none applies.
  Future<DateTime?> bolusRecoveryUntil(DateTime now) =>
      _until(keyBolusFrom, now);

  /// Marks [now] as the end of a bout under each length the running bout has
  /// reached by now.
  Future<void> _bookReachedLengths(DateTime now) async {
    final length = now.difference((await _time(keyStartedAt)) ?? now);
    if (length >= minLength) {
      await _write(keyRecoveryFrom, now);
    }
    final bolusMinutes = await ActivityModeSettings.recoveryBolusMinutes.load();
    if (length >= Duration(minutes: bolusMinutes)) {
      await _write(keyBolusFrom, now);
    }
  }

  /// The end of the recovery that began when the bout booked under [key]
  /// ended, or null when there is none or it has lapsed.
  Future<DateTime?> _until(String key, DateTime now) async {
    final from = await _time(key);
    if (from == null) {
      return null;
    }
    final hours = await ActivityModeSettings.recoveryHours.load();
    final until = from.add(Duration(hours: hours));
    return now.isBefore(until) ? until : null;
  }

  Future<void> _write(String key, DateTime at) =>
      _storage.write(key: key, value: '${at.millisecondsSinceEpoch}');

  Future<DateTime?> _time(String key) async {
    final epochMs = int.tryParse(await _storage.read(key: key) ?? '');
    return epochMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(epochMs);
  }
}
