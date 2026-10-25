import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/activity_mode/activity_mode_settings.dart';

/// The endurance bout the activity mode last saw, and the recovery after it.
///
/// Booked from every endurance reading, whatever its source (a detected walk,
/// a recording, the pulse, a hand choice), so the recovery follows the
/// activity itself rather than one way of noticing it. Readings less than
/// [gap] apart belong to one bout. Only a bout of at least [minLength] earns a
/// recovery: ten minutes to the bus stop is not what drains glycogen.
class ActivityBout {
  const ActivityBout();

  static const _storage = FlutterSecureStorage();
  static const keyStartedAt = 'activity_bout_started_at';
  static const keyLastAt = 'activity_bout_last_at';
  static const gap = Duration(minutes: 15);
  static const minLength = Duration(minutes: 20);

  Future<void> sawEndurance(DateTime now) async {
    final last = await _time(keyLastAt);
    if (last == null || now.difference(last) > gap) {
      await _write(keyStartedAt, now);
    }
    await _write(keyLastAt, now);
  }

  /// When the recovery after the last bout ends, or null when none applies.
  Future<DateTime?> recoveryUntil(DateTime now) async {
    final started = await _time(keyStartedAt);
    final last = await _time(keyLastAt);
    if (started == null ||
        last == null ||
        last.difference(started) < minLength) {
      return null;
    }
    final hours = await ActivityModeSettings.recoveryHours.load();
    final until = last.add(Duration(hours: hours));
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
