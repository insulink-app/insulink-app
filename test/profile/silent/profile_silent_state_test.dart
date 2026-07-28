import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';

import '../../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> storage;

  setUp(() {
    storage = installSecureStorageMock();
  });

  test('defaults to off when nothing is stored', () async {
    expect(await ProfileSilentState.load(), SilentMode.off);
  });

  test('setMode persists each mode and load reads it back', () async {
    final state = ProfileSilentState(SilentMode.off);
    await state.setMode(SilentMode.tones);
    expect(state.mode, SilentMode.tones);
    expect(await ProfileSilentState.load(), SilentMode.tones);
    await state.setMode(SilentMode.all);
    expect(await ProfileSilentState.load(), SilentMode.all);
    await state.setMode(SilentMode.off);
    expect(await ProfileSilentState.load(), SilentMode.off);
  });

  test('setMode is a no-op when the mode is unchanged', () async {
    final state = ProfileSilentState(SilentMode.off);
    await state.setMode(SilentMode.off);
    expect(await ProfileSilentState.load(), SilentMode.off);
  });

  /// The two flags are written together, so only a foreign writer (the panel
  /// pushing a settings blob) can set both — the hard mute must win then.
  test('a hard mute outranks a stale tone flag', () async {
    storage['silent_mode'] = 'true';
    storage['silent_tones'] = 'true';
    expect(await ProfileSilentState.load(), SilentMode.all);
  });

  test('tones mutes the sound but not the notification', () {
    expect(SilentMode.tones.mutesSound, isTrue);
    expect(SilentMode.tones.mutesNotifications, isFalse);
    expect(SilentMode.all.mutesNotifications, isTrue);
    expect(SilentMode.off.mutesSound, isFalse);
  });
}
