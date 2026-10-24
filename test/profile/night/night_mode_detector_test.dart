import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/night/night_mode.dart';
import 'package:insulink/src/profile/night/night_mode_detector.dart';

import '../../support/secure_storage_mock.dart';

/// The automatic night mode: asleep only after a sustained low pulse, awake
/// again on a clear rise or when the pulse stops arriving.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  final start = DateTime(2026, 10, 24, 23);

  void feed(NightModeDetector detector, int bpm, int fromMinute, int toMinute) {
    for (var minute = fromMinute; minute <= toMinute; minute++) {
      detector.onPulse(bpm, start.add(Duration(minutes: minute)));
    }
  }

  test('a pulse below the threshold for 20 minutes is night', () async {
    final detector = NightModeDetector();
    feed(detector, 50, 0, 19);
    expect(detector.asleep, isFalse);
    feed(detector, 50, 20, 20);
    expect(detector.asleep, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(await const NightMode().detected(), isTrue);
  });

  test('one sample above the threshold restarts the 20 minutes', () {
    final detector = NightModeDetector();
    feed(detector, 50, 0, 15);
    feed(detector, 60, 16, 16);
    feed(detector, 50, 17, 30);
    expect(detector.asleep, isFalse);
  });

  test('awake again only on a clear rise, not on a small one', () {
    final detector = NightModeDetector();
    feed(detector, 50, 0, 20);
    feed(detector, 58, 21, 21);
    expect(detector.asleep, isTrue);
    feed(detector, 65, 22, 22);
    expect(detector.asleep, isFalse);
  });

  test('a pulse that stops arriving ends night mode', () async {
    final detector = NightModeDetector();
    feed(detector, 50, 0, 20);
    await detector.refresh(start.add(const Duration(minutes: 31)));
    expect(detector.asleep, isFalse);
  });

  test('a stored night from before a restart is cleared on the first tick', () async {
    await const NightMode().saveDetected(true);
    await NightModeDetector().refresh(start);
    await Future<void>.delayed(Duration.zero);
    expect(await const NightMode().detected(), isFalse);
  });

  test('night mode is active when on, never when off, by the pulse when automatic', () async {
    const nightMode = NightMode();
    await nightMode.saveDetected(true);
    await nightMode.saveChoice(NightModeChoice.off);
    expect(await nightMode.isActive(), isFalse);
    await nightMode.saveChoice(NightModeChoice.auto);
    expect(await nightMode.isActive(), isTrue);
    await nightMode.saveDetected(false);
    await nightMode.saveChoice(NightModeChoice.on);
    expect(await nightMode.isActive(), isTrue);
  });
}
