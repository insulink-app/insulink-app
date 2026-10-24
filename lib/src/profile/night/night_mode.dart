import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/profile/notifications/notification_threshold.dart';

/// Whether night mode is off, on, or switched by the pulse.
enum NightModeChoice { off, on, auto }

/// Night mode: warnings and pre-warnings buzz the Fitbit Air instead of ringing
/// the phone, so a partner sleeps on. Urgent alarms always ring, and a warning
/// whose buzz does not reach the band rings after all (see
/// `G7AlarmManager._alert`), so night mode never makes an alarm silent.
///
/// Read fresh from storage by the service isolate on every alarm, like the
/// other alarm settings; the automatic detection writes its verdict there too
/// ([NightModeDetector]).
class NightMode {
  const NightMode();

  static const _choiceKey = 'night_mode';
  static const _detectedKey = 'night_mode_detected';

  /// The pulse below which automatic night mode counts the wearer as asleep.
  static const pulseThreshold = NotificationThreshold(
    storageKey: 'night_mode_pulse',
    labelKey: 'profile.night.threshold',
    valueKey: 'profile.night.threshold.value',
    defaultValue: 55,
    min: 40,
    max: 80,
  );

  static const _storage = FlutterSecureStorage();

  Future<NightModeChoice> loadChoice() async {
    final raw = await _storage.read(key: _choiceKey);
    return NightModeChoice.values.asNameMap()[raw] ?? NightModeChoice.off;
  }

  Future<void> saveChoice(NightModeChoice choice) =>
      _storage.write(key: _choiceKey, value: choice.name);

  /// Whether the automatic detection currently sees a sleeping wearer.
  Future<bool> detected() async => await _storage.read(key: _detectedKey) == 'true';

  Future<void> saveDetected(bool asleep) =>
      _storage.write(key: _detectedKey, value: '$asleep');

  /// Whether night mode holds the phone's tones back right now.
  Future<bool> isActive() async {
    return switch (await loadChoice()) {
      NightModeChoice.off => false,
      NightModeChoice.on => true,
      NightModeChoice.auto => await detected(),
    };
  }
}
