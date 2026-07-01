import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/g7/service/alarms.dart';
import 'package:insulink/src/g7/store.dart';

import '../../support/secure_storage_mock.dart';

/// Stubs the audioplayers method channels so the `AudioPlayer` the alarm manager
/// constructs doesn't throw `MissingPluginException` (the tone itself is
/// best-effort and irrelevant to the alarm-decision logic under test).
void silenceAudioPlayers() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in const [
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }
}

/// Mocks the flutter_local_notifications platform channel, recording every
/// `show`/`cancel` so the alarm logic can be exercised without a device. Audio
/// is fired through audioplayers, which has no test platform — every alarm path
/// already wraps `play` in a best-effort try/catch, so it no-ops here.
({List<int> shown, List<int> cancelled}) installNotificationMock() {
  final shown = <int>[];
  final cancelled = <int>[];
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        final args = (call.arguments as Map?) ?? const {};
        if (call.method == 'show') {
          shown.add(args['id'] as int);
        } else if (call.method == 'cancel') {
          cancelled.add(args['id'] as int);
        } else if (call.method == 'initialize') {
          return true;
        }
        return null;
      });
  return (shown: shown, cancelled: cancelled);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> storage;
  late ({List<int> shown, List<int> cancelled}) notifications;
  late G7AlarmManager alarms;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    storage = installSecureStorageMock();
    notifications = installNotificationMock();
    silenceAudioPlayers();
    // Register the Android impl so resolvePlatformSpecificImplementation works;
    // its channel is the one mocked above.
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    alarms = G7AlarmManager(
      FlutterLocalNotificationsPlugin(),
      await G7Store.open(),
    );
    await alarms.init();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('trendArrow buckets the per-minute trend', () {
    test('maps each rate to its arrow', () {
      expect(alarms.trendArrow(2.5), '↑');
      expect(alarms.trendArrow(1.0), '↗');
      expect(alarms.trendArrow(0.0), '→');
      expect(alarms.trendArrow(-1.5), '↘');
      expect(alarms.trendArrow(-3.0), '↓');
    });
  });

  group('check is edge-triggered', () {
    test('fires once on entering a zone, not on staying in it', () async {
      await alarms.check(60, -1.0); // low warning
      await alarms.check(58, -1.0); // still low warning
      expect(notifications.shown, [G7AlarmLevel.lowWarning.index]);
    });

    test('fires again when the zone changes', () async {
      await alarms.check(60, -1.0); // low warning
      await alarms.check(50, -1.0); // urgent low
      expect(notifications.shown, [
        G7AlarmLevel.lowWarning.index,
        G7AlarmLevel.lowUrgent.index,
      ]);
    });

    test('an in-range reading raises nothing', () async {
      await alarms.check(100, 0.0);
      expect(notifications.shown, isEmpty);
    });

    test(
      'silent mode suppresses the notification but still tracks the zone',
      () async {
        storage['silent_mode'] = 'true';
        await alarms.check(60, -1.0);
        expect(notifications.shown, isEmpty);
        // Leaving silent: a value still in the SAME zone must not re-fire.
        storage['silent_mode'] = 'false';
        await alarms.check(58, -1.0);
        expect(notifications.shown, isEmpty);
        // Only a fresh crossing fires.
        await alarms.check(50, -1.0);
        expect(notifications.shown, [G7AlarmLevel.lowUrgent.index]);
      },
    );

    test('a null reading is ignored', () async {
      await alarms.check(null, 0.0);
      expect(notifications.shown, isEmpty);
    });
  });

  group('fireTest previews an alarm regardless of zone/silent', () {
    test('high test shows the high-warning notification', () async {
      storage['silent_mode'] = 'true';
      await alarms.fireTest(high: true);
      expect(notifications.shown, [G7AlarmLevel.highWarning.index]);
    });
  });

  group('connection-lost warning', () {
    test(
      'fires once after the outage threshold and clears on a reading',
      () async {
        await alarms.checkConnectionLost(
          sensorLinked: true,
          sinceLastReading: const Duration(minutes: 20),
        );
        await alarms.checkConnectionLost(
          sensorLinked: true,
          sinceLastReading: const Duration(minutes: 25),
        );
        expect(notifications.shown, hasLength(1));
        await alarms.onReading();
        expect(notifications.cancelled, hasLength(1));
      },
    );

    test('stays quiet before the threshold or with no sensor', () async {
      await alarms.checkConnectionLost(
        sensorLinked: true,
        sinceLastReading: const Duration(minutes: 5),
      );
      await alarms.checkConnectionLost(
        sensorLinked: false,
        sinceLastReading: const Duration(hours: 1),
      );
      expect(notifications.shown, isEmpty);
    });
  });

  group('sensor-expiry warning is one-shot per sensor', () {
    test('fires once when under 24 h remain, then stays persisted', () async {
      final store = await G7Store.open();
      Future<void> tick() => alarms.checkExpiry(
        store: store,
        key: 'SERIAL',
        sessionLengthSec: 864000,
        secsSinceStart: 864000 - 3600, // 1 h left
      );
      await tick();
      await tick();
      expect(notifications.shown, hasLength(1));
      expect(store.expiryNotified('SERIAL'), isTrue);
    });

    test('does not fire while plenty of session remains', () async {
      final store = await G7Store.open();
      await alarms.checkExpiry(
        store: store,
        key: 'SERIAL',
        sessionLengthSec: 864000,
        secsSinceStart: 0,
      );
      expect(notifications.shown, isEmpty);
    });
  });
}
