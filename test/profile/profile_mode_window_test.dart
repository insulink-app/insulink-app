import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/profile_mode_window.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  int msFromNow(Duration offset) =>
      DateTime.now().add(offset).millisecondsSinceEpoch;

  test('a window with no end never lapses', () {
    const window = ProfileModeWindow.none();
    expect(window.lapsed, isFalse);
    expect(window.remaining, isNull);
    expect(window.windowMin, ProfileModeWindow.permanent);
  });

  test('a window lapses once its end has passed', () {
    final future = ProfileModeWindow(120, msFromNow(const Duration(minutes: 1)));
    expect(future.lapsed, isFalse);
    expect(future.remaining!.inSeconds, inInclusiveRange(50, 60));

    final past = ProfileModeWindow(120, msFromNow(const Duration(minutes: -1)));
    expect(past.lapsed, isTrue);
    expect(past.remaining, isNull);
  });

  test('withWindow anchors the end from now', () {
    final window = const ProfileModeWindow.none().withWindow(120);
    expect(window.windowMin, 120);
    expect(window.remaining!.inMinutes, inInclusiveRange(118, 120));
  });

  test('withWindow permanent clears the end', () {
    final window = ProfileModeWindow(
      120,
      msFromNow(const Duration(minutes: 30)),
    ).withWindow(ProfileModeWindow.permanent);
    expect(window.until, ProfileModeWindow.permanent);
    expect(window.lapsed, isFalse);
  });

  /// The whole point of keeping the duration next to the end: switching a mode
  /// off and on again must give the FULL window, not the sliver that was left.
  test('started() restarts the picked duration from now', () {
    final almostOver = ProfileModeWindow(
      480,
      msFromNow(const Duration(minutes: 2)),
    );
    final restarted = almostOver.started();
    expect(restarted.windowMin, 480);
    expect(restarted.remaining!.inMinutes, inInclusiveRange(478, 480));
  });

  test('stopped() keeps the duration but ends the run', () {
    final stopped = ProfileModeWindow(
      120,
      msFromNow(const Duration(minutes: 30)),
    ).stopped;
    expect(stopped.windowMin, 120);
    expect(stopped.until, ProfileModeWindow.permanent);
    expect(stopped.lapsed, isFalse);
  });

  test('expiryTimer only exists while there is time left', () {
    expect(const ProfileModeWindow.none().expiryTimer(() {}), isNull);
    final lapsed = ProfileModeWindow(120, msFromNow(const Duration(minutes: -1)));
    expect(lapsed.expiryTimer(() {}), isNull);
    final timer = ProfileModeWindow(
      120,
      msFromNow(const Duration(minutes: 5)),
    ).expiryTimer(() {});
    expect(timer, isNotNull);
    timer!.cancel();
  });

  group('store', () {
    late Map<String, String> storage;
    const store = ProfileModeWindowStore('test_window_min', 'test_until');

    setUp(() {
      storage = installSecureStorageMock();
    });

    test('round-trips both values', () async {
      final saved = const ProfileModeWindow.none().withWindow(120);
      await store.save(saved);
      expect(await store.load(), saved);
    });

    /// A mute or saver must never expire by accident, so anything unreadable
    /// reads as "no limit" rather than as an elapsed one.
    test('absent or unparseable values read as no limit', () async {
      expect(await store.load(), const ProfileModeWindow.none());
      storage['test_until'] = 'soon';
      storage['test_window_min'] = '';
      expect(await store.load(), const ProfileModeWindow.none());
    });
  });
}
