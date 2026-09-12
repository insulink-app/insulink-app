import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/notifications/alarm_tone.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_sound_state.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_tone_state.dart';
import 'package:insulink/src/profile/notifications/profile_connection_state.dart';

import '../../support/secure_storage_mock.dart';

/// Both flags share the same shape: default ON (safety-relevant), only `'false'`
/// turns them off. They use distinct storage keys, so toggling one leaves the
/// other untouched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  test('alarm sound defaults ON and round-trips through save', () async {
    final state = ProfileAlarmSoundState();
    expect(await state.load(), isTrue);
    await state.save(false);
    expect(await state.load(), isFalse);
    await state.save(true);
    expect(await state.load(), isTrue);
  });

  test('connection-lost defaults ON and round-trips through save', () async {
    final state = ProfileConnectionState();
    expect(await state.load(), isTrue);
    await state.save(false);
    expect(await state.load(), isFalse);
  });

  test('the two flags use independent keys', () async {
    await ProfileAlarmSoundState().save(false);
    expect(await ProfileConnectionState().load(), isTrue);
  });

  test(
    'each alarm stores its tone under its own key, classic by default',
    () async {
      final state = ProfileAlarmToneState();
      expect(await state.load(AlarmSlot.lowUrgent), AlarmTone.classic);
      await state.save(AlarmSlot.lowUrgent, AlarmTone.short);
      expect(await state.load(AlarmSlot.lowUrgent), AlarmTone.short);
      expect(await state.load(AlarmSlot.lowWarning), AlarmTone.classic);
    },
  );
}
