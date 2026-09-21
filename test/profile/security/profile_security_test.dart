import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/biometric_auth.dart';
import 'package:insulink/src/profile/security/profile_security_state.dart';

import '../../support/secure_storage_mock.dart';

/// What the switches are allowed to change, and what they are not: a gate the
/// user turned off must let its action through without a sheet, and every gate
/// the user has never touched must still be the gate it was before the setting
/// existed.
class _RecordingAuth extends BiometricAuth {
  _RecordingAuth(this._answer);

  final bool _answer;

  int prompts = 0;

  @override
  Future<bool> prompt(
    String reason, {
    bool allowDeviceCredential = false,
  }) async {
    prompts++;
    return _answer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> backing;

  setUp(() {
    backing = installSecureStorageMock();
  });

  test('an untouched install gates everything but the app itself', () async {
    final security = ProfileSecurityState(auth: _RecordingAuth(true));
    for (final action in GuardedAction.values) {
      expect(
        await security.isGuarded(action),
        action != GuardedAction.appEntry,
        reason: '${action.name} default',
      );
    }
  });

  test('a gate the user switched off lets the action through unasked', () async {
    final auth = _RecordingAuth(true);
    final security = ProfileSecurityState(auth: auth);
    await security.setGuarded(GuardedAction.bolus, false);
    expect(await security.confirm(GuardedAction.bolus, 'reason'), isTrue);
    expect(auth.prompts, 0);
    expect(backing['guard_bolus'], 'false');
  });

  test('a gate that is on asks before it answers', () async {
    final auth = _RecordingAuth(true);
    final security = ProfileSecurityState(auth: auth);
    expect(await security.confirm(GuardedAction.bolus, 'reason'), isTrue);
    expect(auth.prompts, 1);
  });

  test('a declined check stops the action', () async {
    final auth = _RecordingAuth(false);
    final security = ProfileSecurityState(auth: auth);
    expect(await security.confirm(GuardedAction.cannula, 'reason'), isFalse);
    expect(auth.prompts, 1);
  });

  test('a switch outlives the object that flipped it', () async {
    await ProfileSecurityState().setGuarded(GuardedAction.appEntry, true);
    final later = ProfileSecurityState();
    expect(await later.isGuarded(GuardedAction.appEntry), isTrue);
  });

  test('every action has a locale key of its own', () async {
    final keys = GuardedAction.values.map((action) => action.labelKey).toSet();
    expect(keys.length, GuardedAction.values.length);
    expect(
      GuardedAction.appEntry.labelKey,
      'profile.security.action.app_entry',
    );
  });
}
