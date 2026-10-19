import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/profile/remote_review/remote_settings_review.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';

import '../support/secure_storage_mock.dart';

/// The account's settings blob can be written from outside the app. Adopting
/// it must never reach the pod key, the tokens or the live automation mode, and
/// a change to a dose or an alarm waits for the user on the phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, String> storage;

  setUp(() {
    storage = installSecureStorageMock();
  });

  test('keys the app would never push are not adopted', () async {
    storage['pod.ltk'] = 'the real key';
    await ProfileSettings().adopt({
      'pod.ltk': 'attacker key',
      'authentication_token': 'attacker token',
      'pod.loop_mode': 'engaged',
    });
    expect(storage['pod.ltk'], 'the real key');
    expect(storage.containsKey('authentication_token'), isFalse);
    expect(storage.containsKey('pod.loop_mode'), isFalse);
  });

  test('a dosing change is held, not written', () async {
    await ProfileSettings().adopt({'bolus_correction_factor': '20'});
    expect(storage.containsKey('bolus_correction_factor'), isFalse);
    expect(await const RemoteSettingsReview().pending(),
        {'bolus_correction_factor': '20'});
    expect(await const RemoteSettingsReview().groups(),
        [RemoteSettingsGroup.dosing]);
  });

  test('muting the alarms and dropping a fingerprint gate are held too', () async {
    await ProfileSettings().adopt({'silent_mode': 'true', 'guard_bolus': 'false'});
    expect(storage.containsKey('silent_mode'), isFalse);
    expect(storage.containsKey('guard_bolus'), isFalse);
    expect(await const RemoteSettingsReview().groups(),
        [RemoteSettingsGroup.alarms, RemoteSettingsGroup.locks]);
  });

  test('a reviewed value equal to the one in use is not held', () async {
    await ProfileSettings().adopt({
      'bolus_correction_factor': '${ProfileBolusState.defCorrection}',
    });
    expect(await const RemoteSettingsReview().pending(), isEmpty);
  });

  test('everything else is adopted directly', () async {
    await ProfileSettings().adopt({'sport.steps_goal': '12000', 'language': 'de'});
    expect(storage['sport.steps_goal'], '12000');
    expect(storage['language'], 'de');
  });

  test('a confirmed change is written and no longer held', () async {
    await ProfileSettings().adopt({'bolus_max': '15'});
    await const RemoteSettingsReview().apply();
    expect(storage['bolus_max'], '15');
    expect(await const RemoteSettingsReview().pending(), isEmpty);
  });

  /// Even a confirmed value is held to what the editors allow.
  test('stored values past the editor bounds are clamped when read', () async {
    storage['bolus_correction_factor'] = '1';
    storage['bolus_max'] = '500';
    storage[LoopLimits.keyMaxIob] = '1000';
    storage[LoopLimits.keyMaxRate] = '30';
    final bolus = await ProfileBolusState.load();
    final limits = await LoopLimits.load();
    expect(bolus.correctionFactor, ProfileBolusState.minCorrection);
    expect(bolus.maxBolus, ProfileBolusState.maxMaxBolus);
    expect(limits.maxIobUnits, 15);
    expect(limits.maxUnitsPerHour, 10);
  });
}
