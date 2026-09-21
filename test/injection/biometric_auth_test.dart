import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/biometric_auth.dart';

/// The incident this file exists for: the fingerprint was accepted, the phone
/// was locked in the belief that the bolus was on its way, and minutes later the
/// screen said "authentication failed". Android reports the prompt it tears down
/// on screen-off as an ordinary rejection, and that cancel can beat the pause
/// the plugin's own sticky retry watches for, so the accepted finger was thrown
/// away. Only an answer given with the app in front of the user counts.
class _ScriptedAuth extends BiometricAuth {
  _ScriptedAuth(this._answers);

  final List<bool> _answers;

  final List<String> reasons = [];

  final List<bool> credentialPolicies = [];

  int get prompts => reasons.length;

  @override
  Future<bool> prompt(
    String reason, {
    bool allowDeviceCredential = false,
  }) async {
    reasons.add(reason);
    credentialPolicies.add(allowDeviceCredential);
    return _answers.removeAt(0);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> lifecycle(AppLifecycleState state) {
    return binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage('$state'),
      (_) {},
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    await lifecycle(AppLifecycleState.resumed);
  });

  test('a refusal given in the foreground is the answer', () async {
    final auth = _ScriptedAuth([false]);
    expect(await auth.confirm('reason'), isFalse);
    expect(auth.prompts, 1);
  });

  test('a confirmed finger is not asked for twice', () async {
    final auth = _ScriptedAuth([true]);
    expect(await auth.confirm('reason'), isTrue);
    expect(auth.prompts, 1);
  });

  test('a prompt killed by screen-off asks again on unlock', () async {
    final auth = _ScriptedAuth([false, true]);
    final confirmed = auth.confirm('reason');
    await settle();
    await lifecycle(AppLifecycleState.paused);
    await settle();
    expect(auth.prompts, 1, reason: 'nothing prompts a dark screen');
    await lifecycle(AppLifecycleState.resumed);
    expect(await confirmed, isTrue);
    expect(auth.prompts, 2);
  });

  test('a rejection that arrives with the app already away is retried', () async {
    await lifecycle(AppLifecycleState.paused);
    final auth = _ScriptedAuth([false, true]);
    final confirmed = auth.confirm('reason');
    await settle();
    expect(auth.prompts, 1);
    await lifecycle(AppLifecycleState.resumed);
    expect(await confirmed, isTrue);
    expect(auth.prompts, 2);
  });

  test('the retry asks for the same thing the first prompt did', () async {
    final auth = _ScriptedAuth([false, true]);
    final confirmed = auth.confirm('bolus', allowDeviceCredential: true);
    await settle();
    await lifecycle(AppLifecycleState.paused);
    await settle();
    await lifecycle(AppLifecycleState.resumed);
    await confirmed;
    expect(auth.reasons, ['bolus', 'bolus']);
    expect(auth.credentialPolicies, [true, true]);
  });

  test('the shade coming down is not an interruption', () async {
    final auth = _ScriptedAuth([false]);
    final confirmed = auth.confirm('reason');
    await settle();
    await lifecycle(AppLifecycleState.inactive);
    expect(await confirmed, isFalse);
    expect(auth.prompts, 1, reason: 'a visible app can be refused for real');
    await lifecycle(AppLifecycleState.resumed);
  });

  test('the second prompt is the last one, whatever the screen does', () async {
    final auth = _ScriptedAuth([false, false]);
    final confirmed = auth.confirm('reason');
    await settle();
    await lifecycle(AppLifecycleState.paused);
    await settle();
    await lifecycle(AppLifecycleState.resumed);
    expect(await confirmed, isFalse, reason: 'no endless prompting');
    expect(auth.prompts, 2);
  });
}
