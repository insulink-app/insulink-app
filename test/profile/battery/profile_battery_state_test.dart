import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/battery/profile_battery_state.dart';
import 'package:insulink/src/profile/profile_mode_window.dart';

import '../../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> storage;

  setUp(() {
    storage = installSecureStorageMock();
  });

  int msFromNow(Duration offset) =>
      DateTime.now().add(offset).millisecondsSinceEpoch;

  ProfileBatteryState freshState() =>
      ProfileBatteryState(BatteryMode.off, const ProfileModeWindow.none());

  test('defaults to off with no limit', () async {
    expect(await ProfileBatteryState.loadActive(), BatteryMode.off);
    expect((await ProfileBatteryState.load()).window.remaining, isNull);
  });

  test('setMode persists each level and load reads it back', () async {
    final state = freshState();
    await state.setMode(BatteryMode.saving);
    expect(await ProfileBatteryState.loadActive(), BatteryMode.saving);
    await state.setMode(BatteryMode.extreme);
    expect(await ProfileBatteryState.loadActive(), BatteryMode.extreme);
    await state.setMode(BatteryMode.off);
    expect(await ProfileBatteryState.loadActive(), BatteryMode.off);
  });

  test('a lapsed window turns the saver off for every reader', () async {
    storage['battery_saver_mode'] = 'saving';
    storage['battery_saver_window_min'] = '120';
    storage['battery_saver_until'] = '${msFromNow(const Duration(minutes: 1))}';
    expect(await ProfileBatteryState.loadActive(), BatteryMode.saving);

    storage['battery_saver_until'] = '${msFromNow(const Duration(minutes: -1))}';
    expect(await ProfileBatteryState.loadActive(), BatteryMode.off);
    expect((await ProfileBatteryState.load()).activeMode, BatteryMode.off);
  });

  /// The duration survives a lapse so re-arming the same window is one tap.
  test('a lapsed run keeps its duration but clears the end', () async {
    storage['battery_saver_mode'] = 'extreme';
    storage['battery_saver_window_min'] = '480';
    storage['battery_saver_until'] = '${msFromNow(const Duration(minutes: -1))}';
    final stored = await ProfileBatteryState.loadRaw();
    expect(stored.mode, BatteryMode.off);
    expect(stored.window.windowMin, 480);
    expect(stored.window.until, ProfileModeWindow.permanent);
  });

  test('a saver with no limit never lapses', () async {
    storage['battery_saver_mode'] = 'saving';
    storage['battery_saver_until'] = '${ProfileModeWindow.permanent}';
    expect(await ProfileBatteryState.loadActive(), BatteryMode.saving);
  });

  test('switching off then on restarts the full window', () async {
    final state = freshState();
    await state.setMode(BatteryMode.saving);
    await state.setWindow(120);
    expect(state.window.remaining!.inMinutes, inInclusiveRange(118, 120));

    await state.setMode(BatteryMode.off);
    expect(state.window.until, ProfileModeWindow.permanent);
    await state.setMode(BatteryMode.extreme);
    expect(state.window.remaining!.inMinutes, inInclusiveRange(118, 120));
  });

  test('an unknown stored mode falls back to off', () async {
    storage['battery_saver_mode'] = 'aggressive';
    expect(await ProfileBatteryState.loadActive(), BatteryMode.off);
  });

  test('each level gates the right work', () {
    expect(BatteryMode.off.pausesDetection, isFalse);
    expect(BatteryMode.off.slowsHeartRatePoll, isFalse);
    expect(BatteryMode.saving.pausesDetection, isTrue);
    expect(BatteryMode.saving.slowsHeartRatePoll, isTrue);
    // The band and the forecast survive the plain saver — only extreme drops them.
    expect(BatteryMode.saving.pausesBand, isFalse);
    expect(BatteryMode.saving.pausesPrediction, isFalse);
    expect(BatteryMode.extreme.pausesBand, isTrue);
    expect(BatteryMode.extreme.pausesPrediction, isTrue);
  });
}
