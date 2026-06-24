import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/g7/store.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  test('saveReadings/loadReadings round-trips the int-map codec', () async {
    final store = await G7Store.open();
    await store.saveReadings('serialA', {0: 100, 300: 110, 600: 120});
    expect(store.loadReadings('serialA'), {0: 100, 300: 110, 600: 120});
  });

  test('loadReadings returns empty for an unknown serial', () async {
    final store = await G7Store.open();
    expect(store.loadReadings('nope'), isEmpty);
  });

  test('saveReadings keeps only the most recent ~300 points', () async {
    final store = await G7Store.open();
    final many = {for (var index = 0; index < 400; index++) index * 300: 100};
    await store.saveReadings('serialA', many);
    final loaded = store.loadReadings('serialA');
    expect(loaded, hasLength(300));
    // The newest key survives, the oldest is dropped.
    expect(loaded.containsKey(399 * 300), isTrue);
    expect(loaded.containsKey(0), isFalse);
  });

  test('session key hex-encodes and decodes round-trip', () async {
    final store = await G7Store.open();
    final key = Uint8List.fromList(
      List<int>.generate(16, (index) => index * 7 % 256),
    );
    await store.saveSessionKey('serialA', key);
    expect(store.sessionKey('serialA'), key);
  });

  test('sessionKey is null when none stored', () async {
    final store = await G7Store.open();
    expect(store.sessionKey('serialA'), isNull);
  });

  group('long-term archive', () {
    test(
      'archiveRange returns readings within the window, key-sorted',
      () async {
        final store = await G7Store.open();
        await store.archiveAddAll({
          DateTime(2024, 1, 1, 10, 0): 100,
          DateTime(2024, 1, 1, 10, 5): 110,
          DateTime(2024, 1, 2, 10, 0): 130, // next day
        });
        final sameDay = store.archiveRange(
          DateTime(2024, 1, 1, 9),
          DateTime(2024, 1, 1, 11),
        );
        expect(sameDay.values.toList(), [100, 110]);

        final both = store.archiveRange(
          DateTime(2024, 1, 1),
          DateTime(2024, 1, 3),
        );
        expect(both.values.toList(), [100, 110, 130]);
      },
    );

    test('readings on the same minute dedupe', () async {
      final store = await G7Store.open();
      await store.archiveAdd(DateTime(2024, 1, 1, 10, 0, 10), 100);
      await store.archiveAdd(DateTime(2024, 1, 1, 10, 0, 50), 105);
      final range = store.archiveRange(
        DateTime(2024, 1, 1, 9),
        DateTime(2024, 1, 1, 11),
      );
      expect(range.values.toList(), [105]); // last write wins for that minute
    });

    test('archivePrune drops day-chunks older than the kept window', () async {
      final store = await G7Store.open();
      final old = DateTime.now().subtract(const Duration(days: 100));
      final recent = DateTime.now().subtract(const Duration(minutes: 5));
      await store.archiveAddAll({old: 100, recent: 120});
      await store.archivePrune(const Duration(days: 90));
      final all = store.archiveRange(
        DateTime.now().subtract(const Duration(days: 200)),
        DateTime.now().add(const Duration(minutes: 1)),
      );
      expect(all.values.toList(), [120]);
    });

    test('clearSensor wipes the session cache but KEEPS the archive', () async {
      final store = await G7Store.open();
      await store.saveReadings('serialA', {0: 100});
      await store.saveSessionKey(
        'serialA',
        Uint8List.fromList(List.filled(16, 1)),
      );
      await store.archiveAddAll({DateTime(2024, 1, 1, 10): 100});

      await store.clearSensor('serialA');

      expect(store.loadReadings('serialA'), isEmpty);
      expect(store.sessionKey('serialA'), isNull);
      final archive = store.archiveRange(
        DateTime(2024, 1, 1),
        DateTime(2024, 1, 2),
      );
      expect(archive.values.toList(), [100]);
    });
  });

  group('latest reading + metadata', () {
    test('saveLatest/loadLatest round-trips the headline reading', () async {
      final store = await G7Store.open();
      await store.saveLatest(
        'serialA',
        mgdl: 123,
        trendTenths: -3,
        state: 6,
        secsSinceStart: 4200,
      );
      final latest = store.loadLatest('serialA');
      expect(latest, {'mgdl': 123, 'trend': -3, 'state': 6, 'secs': 4200});
    });

    test('loadLatest is null when none stored', () async {
      final store = await G7Store.open();
      expect(store.loadLatest('serialA'), isNull);
    });

    test('expiryNotified is a one-shot, cleared by clearSensor', () async {
      final store = await G7Store.open();
      expect(store.expiryNotified('serialA'), isFalse);
      await store.setExpiryNotified('serialA');
      expect(store.expiryNotified('serialA'), isTrue);
      await store.clearSensor('serialA');
      expect(store.expiryNotified('serialA'), isFalse);
    });

    test('resolved key and device id persist', () async {
      final store = await G7Store.open();
      await store.saveResolvedKey('AA:BB');
      await store.saveDeviceId('AA:BB', 'AA:BB:CC');
      expect(store.resolvedKey, 'AA:BB');
      expect(store.deviceId('AA:BB'), 'AA:BB:CC');
    });
  });

  test('reload observes writes made through another isolate', () async {
    final backing = installSecureStorageMock();
    final store = await G7Store.open();
    expect(store.loadReadings('serialA'), isEmpty);
    // Simulate the service isolate writing directly to the backing store.
    backing['g7.readings.serialA'] = '0:100,300:110';
    await store.reload();
    expect(store.loadReadings('serialA'), {0: 100, 300: 110});
  });
}
