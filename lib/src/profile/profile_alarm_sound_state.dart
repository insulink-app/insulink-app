import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether glucose alarms play their audible tone. When off, the alarm
/// notification still shows visually — only the sound through the ALARM stream
/// is suppressed. Read fresh by the service isolate's alarm check (which can't
/// observe a notifier — same constraint as [ProfileSilentState]), so a toggle
/// takes effect without restarting the service.
class ProfileAlarmSoundState {
  static const _key = 'alarm_sound';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Default ON — an unheard low alarm is safety-relevant.
  Future<bool> load() async => (await _storage.read(key: _key)) != 'false';

  Future<void> save(bool v) => _storage.write(key: _key, value: '$v');
}
