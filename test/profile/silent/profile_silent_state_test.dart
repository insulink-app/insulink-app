import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/profile_mode_window.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';

import '../../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> storage;

  setUp(() {
    storage = installSecureStorageMock();
  });

  int msFromNow(Duration offset) =>
      DateTime.now().add(offset).millisecondsSinceEpoch;

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

  /// The safety-relevant half of the timed mute: the alarm code only ever calls
  /// `load()`, so a lapsed window must un-mute with no other code involved.
  test('a lapsed window un-mutes for the alarm code', () async {
    storage['silent_mode'] = 'true';
    storage['silent_window_min'] = '120';
    storage['silent_until'] = '${msFromNow(const Duration(minutes: 1))}';
    expect(await ProfileSilentState.load(), SilentMode.all);

    storage['silent_until'] = '${msFromNow(const Duration(minutes: -1))}';
    expect(await ProfileSilentState.load(), SilentMode.off);
  });

  /// A mute set before this feature existed has no window keys at all — it must
  /// stay muted, not expire the moment the app updates.
  test('a mute with no window keys never lapses', () async {
    storage['silent_tones'] = 'true';
    expect(await ProfileSilentState.load(), SilentMode.tones);
    expect(
      (await ProfileSilentState.loadRaw()).window.until,
      ProfileModeWindow.permanent,
    );
  });

  test('setWindow limits the current mute and setMode restarts it', () async {
    final state = ProfileSilentState(SilentMode.off);
    await state.setMode(SilentMode.tones);
    await state.setWindow(120);
    expect(state.window.remaining!.inMinutes, inInclusiveRange(118, 120));
    expect((await ProfileSilentState.loadRaw()).window.windowMin, 120);

    await state.setMode(SilentMode.off);
    expect(state.window.until, ProfileModeWindow.permanent);
    await state.setMode(SilentMode.tones);
    expect(state.window.remaining!.inMinutes, inInclusiveRange(118, 120));
  });
}
