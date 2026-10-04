import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/profile/notifications/alarm_tone.dart';

/// Which tone style each alarm plays. Read fresh by the service isolate's alarm
/// code (which can't observe a notifier — same constraint as
/// [ProfileAlarmSoundState]), so a change takes effect without restarting the
/// service.
class ProfileAlarmToneState {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Defaults to [AlarmTone.classic] — an unset or unknown value keeps the tone
  /// the app has always played.
  Future<AlarmTone> load(AlarmSlot slot) async {
    final stored = await _storage.read(key: slot.toneStorageKey);
    return AlarmTone.values.firstWhere(
      (tone) => tone.name == stored,
      orElse: () => AlarmTone.classic,
    );
  }

  Future<void> save(AlarmSlot slot, AlarmTone tone) =>
      _storage.write(key: slot.toneStorageKey, value: tone.name);

  /// The asset [slot] currently plays, or null when its tone is switched off.
  Future<String?> assetFor(AlarmSlot slot) async =>
      (await load(slot)).assetFor(slot);

  Future<Map<AlarmSlot, AlarmTone>> loadAll() async {
    final tones = <AlarmSlot, AlarmTone>{};
    for (final slot in AlarmSlot.values) {
      tones[slot] = await load(slot);
    }
    return tones;
  }
}
