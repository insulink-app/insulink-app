import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/battery/profile_battery_state.dart';

import '../../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> storage;

  setUp(() {
    storage = installSecureStorageMock();
  });

  int msFromNow(Duration offset) =>
      DateTime.now().add(offset).millisecondsSinceEpoch;

  test('defaults to off, permanent', () async {
    expect(await ProfileBatteryState.loadActive(), BatteryMode.off);
    final state = await ProfileBatteryState.load();
    expect(state.windowMin, ProfileBatteryState.permanent);
    expect(state.remaining, isNull);
  });

  test('setMode persists the mode and load reads it back', () async {
    final state = ProfileBatteryState(
      BatteryMode.off,
      ProfileBatteryState.permanent,
      ProfileBatteryState.permanent,
    );
    await state.setMode(BatteryMode.saving);
    expect(await ProfileBatteryState.loadActive(), BatteryMode.saving);
    await state.setMode(BatteryMode.extreme);
    expect(await ProfileBatteryState.loadActive(), BatteryMode.extreme);
    await state.setMode(BatteryMode.off);
    expect(await ProfileBatteryState.loadActive(), BatteryMode.off);
  });

  test('a window turns the saver off once it lapses', () async {
    storage['battery_saver_mode'] = 'saving';
    storage['battery_saver_window_min'] = '120';
    storage['battery_saver_until'] = '${msFromNow(const Duration(minutes: 1))}';
    expect(await ProfileBatteryState.loadActive(), BatteryMode.saving);

    storage['battery_saver_until'] = '${msFromNow(const Duration(minutes: -1))}';
    expect(await ProfileBatteryState.loadActive(), BatteryMode.off);
    expect((await ProfileBatteryState.load()).activeMode, BatteryMode.off);
  });

  /// The window is kept across a lapse so re-arming the same duration is one tap.
  test('a lapsed window keeps its duration but clears the end', () async {
    storage['battery_saver_mode'] = 'extreme';
    storage['battery_saver_window_min'] = '480';
    storage['battery_saver_until'] = '${msFromNow(const Duration(minutes: -1))}';
    final stored = await ProfileBatteryState.loadRaw();
    expect(stored.mode, BatteryMode.off);
    expect(stored.windowMin, 480);
    expect(stored.until, ProfileBatteryState.permanent);
  });

  test('a permanent saver never lapses', () async {
    storage['battery_saver_mode'] = 'saving';
    storage['battery_saver_until'] = '${ProfileBatteryState.permanent}';
    expect(await ProfileBatteryState.loadActive(), BatteryMode.saving);
    expect((await ProfileBatteryState.load()).remaining, isNull);
  });

  test('setWindow anchors the end from now and setMode re-anchors it', () async {
    final state = ProfileBatteryState(
      BatteryMode.off,
      ProfileBatteryState.permanent,
      ProfileBatteryState.permanent,
    );
    await state.setMode(BatteryMode.saving);
    await state.setWindow(120);
    expect(state.windowMin, 120);
    expect(state.remaining!.inMinutes, inInclusiveRange(118, 120));

    // Turning it off clears the end; turning it back on gives the FULL window
    // again rather than the sliver that was left.
    await state.setMode(BatteryMode.off);
    expect(state.until, ProfileBatteryState.permanent);
    await state.setMode(BatteryMode.extreme);
    expect(state.remaining!.inMinutes, inInclusiveRange(118, 120));
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
