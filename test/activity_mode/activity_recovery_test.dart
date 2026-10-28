import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/activity_mode/activity_mode.dart';
import 'package:insulink/src/activity_mode/activity_mode_adjustment.dart';
import 'package:insulink/src/activity_mode/activity_mode_store.dart';
import 'package:insulink/src/activity_mode/activity_mode_settings.dart';
import 'package:insulink/src/activity_mode/activity_pulse_detector.dart';
import 'package:insulink/src/activity_mode/recovery_bolus.dart';

import '../support/secure_storage_mock.dart';

/// The lows of an active day come after the activity: the recovery keeps the
/// loop careful for hours, and the pulse notices activity the GPS does not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final start = DateTime(2026, 10, 15, 17);
  const store = ActivityModeStore();

  setUp(installSecureStorageMock);

  Future<(ActivityMode, ActivityModeSource)> modeAt(DateTime at) async {
    final reading = await store.current(at);
    return (reading.mode, reading.source);
  }

  /// Walks for [length] from [from], with the loop reading the mode every
  /// five minutes.
  Future<DateTime> walk(Duration length, {DateTime? from}) async {
    final begin = from ?? start;
    var at = begin;
    while (!at.isAfter(begin.add(length))) {
      await store.markDetected(true, at);
      await store.current(at);
      at = at.add(const Duration(minutes: 5));
    }
    await store.markDetected(false, at);
    return begin.add(length);
  }

  test('a long walk is followed by six hours of recovery', () async {
    final end = await walk(const Duration(minutes: 40));

    expect(await modeAt(end.add(const Duration(minutes: 30))), (
      ActivityMode.recovery,
      ActivityModeSource.recovery,
    ));
    expect(
      (await ActivityModeAdjustment.load(
        end.add(const Duration(hours: 1)),
      )).basalPercent,
      80,
    );
    expect(await modeAt(end.add(const Duration(hours: 6, minutes: 1))), (
      ActivityMode.normal,
      ActivityModeSource.none,
    ));
  });

  test('a short walk earns no recovery', () async {
    final end = await walk(const Duration(minutes: 10));

    expect(await modeAt(end.add(const Duration(minutes: 30))), (
      ActivityMode.normal,
      ActivityModeSource.none,
    ));
  });

  test('a short walk after a long one keeps the recovery', () async {
    final longEnd = await walk(const Duration(minutes: 50));
    final shortEnd = await walk(
      const Duration(minutes: 10),
      from: longEnd.add(const Duration(hours: 2)),
    );

    expect(await modeAt(shortEnd.add(const Duration(minutes: 30))), (
      ActivityMode.recovery,
      ActivityModeSource.recovery,
    ));
  });

  group('recovery bolus', () {
    setUp(() => ActivityModeSettings.recoveryBolus.save(20));

    test('a ride to work leaves the bolus alone', () async {
      final end = await walk(const Duration(minutes: 20));

      final cut = await RecoveryBolus.load(end.add(const Duration(hours: 1)));

      expect(cut.applies, isFalse);
      expect(cut.reduce(5), 5);
    });

    test('a long walk lowers the bolus for the recovery hours', () async {
      final end = await walk(const Duration(minutes: 50));

      final cut = await RecoveryBolus.load(end.add(const Duration(hours: 3)));
      final lapsed = await RecoveryBolus.load(
        end.add(const Duration(hours: 6, minutes: 1)),
      );

      expect(cut.reduce(5), closeTo(4, 1e-9));
      expect(lapsed.applies, isFalse);
    });

    test('the bolus is never cut while the setting is 0', () async {
      await ActivityModeSettings.recoveryBolus.save(0);
      final end = await walk(const Duration(minutes: 50));

      final cut = await RecoveryBolus.load(end.add(const Duration(hours: 1)));

      expect(cut.applies, isFalse);
    });
  });

  test('a pulse held above the threshold is endurance', () async {
    final detector = ActivityPulseDetector();
    for (var minute = 0; minute <= 10; minute++) {
      detector.onPulse(
        minute == 5 ? 105 : 120,
        start.add(Duration(minutes: minute)),
      );
    }
    await Future<void>.delayed(Duration.zero);

    expect(await modeAt(start.add(const Duration(minutes: 11))), (
      ActivityMode.endurance,
      ActivityModeSource.pulse,
    ));
  });

  test('a pulse that drops well below starts the clock again', () async {
    final detector = ActivityPulseDetector();
    for (var minute = 0; minute <= 10; minute++) {
      detector.onPulse(
        minute == 5 ? 90 : 120,
        start.add(Duration(minutes: minute)),
      );
    }
    await Future<void>.delayed(Duration.zero);

    expect(await modeAt(start.add(const Duration(minutes: 11))), (
      ActivityMode.normal,
      ActivityModeSource.none,
    ));
  });
}
