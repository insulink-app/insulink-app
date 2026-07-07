import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/cgm_store.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  test('saveReadings/loadReadings round-trips the int-map codec', () async {
    final store = await CgmStore.open();
    await store.saveReadings('serialA', {0: 100, 300: 110, 600: 120});
    expect(store.loadReadings('serialA'), {0: 100, 300: 110, 600: 120});
  });

  test('loadReadings returns empty for an unknown serial', () async {
    final store = await CgmStore.open();
    expect(store.loadReadings('nope'), isEmpty);
  });

  test('saveReadings keeps only the most recent 24 h by time', () async {
    final store = await CgmStore.open();
    // 48 h of 5-min points; only the last 24 h (relative to the newest key)
    // should survive, regardless of point count/cadence.
    final many = {for (var index = 0; index <= 576; index++) index * 300: 100};
    await store.saveReadings('serialA', many);
    final loaded = store.loadReadings('serialA');
    final newest = 576 * 300;
    expect(loaded.containsKey(newest), isTrue);
    expect(loaded.containsKey(newest - 24 * 3600), isTrue);
    expect(loaded.containsKey(newest - 24 * 3600 - 300), isFalse);
    expect(loaded.containsKey(0), isFalse);
  });

  test('session key hex-encodes and decodes round-trip', () async {
    final store = await CgmStore.open();
    final key = Uint8List.fromList(
      List<int>.generate(16, (index) => index * 7 % 256),
    );
    await store.saveSessionKey('serialA', key);
    expect(store.sessionKey('serialA'), key);
  });

  test('sessionKey is null when none stored', () async {
    final store = await CgmStore.open();
    expect(store.sessionKey('serialA'), isNull);
  });

  group('long-term archive', () {
    test(
      'archiveRange returns readings within the window, key-sorted',
      () async {
        final store = await CgmStore.open();
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
      final store = await CgmStore.open();
      await store.archiveAdd(DateTime(2024, 1, 1, 10, 0, 10), 100);
      await store.archiveAdd(DateTime(2024, 1, 1, 10, 0, 50), 105);
      final range = store.archiveRange(
        DateTime(2024, 1, 1, 9),
        DateTime(2024, 1, 1, 11),
      );
      expect(range.values.toList(), [105]); // last write wins for that minute
    });

    test('archivePrune drops day-chunks older than the kept window', () async {
      final store = await CgmStore.open();
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
      final store = await CgmStore.open();
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
      final store = await CgmStore.open();
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
      final store = await CgmStore.open();
      expect(store.loadLatest('serialA'), isNull);
    });

    test('expiryNotified is a one-shot, cleared by clearSensor', () async {
      final store = await CgmStore.open();
      expect(store.expiryNotified('serialA'), isFalse);
      await store.setExpiryNotified('serialA');
      expect(store.expiryNotified('serialA'), isTrue);
      await store.clearSensor('serialA');
      expect(store.expiryNotified('serialA'), isFalse);
    });

    test('resolved key and device id persist', () async {
      final store = await CgmStore.open();
      await store.saveResolvedKey('AA:BB');
      await store.saveDeviceId('AA:BB', 'AA:BB:CC');
      expect(store.resolvedKey, 'AA:BB');
      expect(store.deviceId('AA:BB'), 'AA:BB:CC');
    });
  });

  group('event log', () {
    test(
      'filters by window, newest first, and is kept by clearSensor',
      () async {
        final store = await CgmStore.open();
        final now = DateTime.now();
        await store.addEvent(
          'new_sensor',
          at: now.subtract(const Duration(days: 10)),
        );
        await store.addEvent(
          'glucose_low',
          at: now.subtract(const Duration(days: 1)),
        );
        await store.addEvent(
          'signal_loss',
          at: now.subtract(const Duration(hours: 1)),
        );

        final recent = store.eventsBetween(
          now.subtract(const Duration(days: 7)),
          now,
        );
        expect(recent.map((event) => event.type), [
          'signal_loss',
          'glucose_low',
        ]);

        await store.clearSensor('serialA');
        expect(
          store.eventsBetween(now.subtract(const Duration(days: 30)), now),
          hasLength(3),
        );
      },
    );

    test(
      'mergeEvents adds new events but skips existing (ts,type) pairs',
      () async {
        final store = await CgmStore.open();
        final base = DateTime(2026, 1, 1, 12);
        await store.addEvent('glucose_low', at: base, value: 62);

        await store.mergeEvents([
          // Same (ts,type) as the existing one → skipped, no duplicate.
          (time: base, type: 'glucose_low', value: 62),
          // Same instant, different type → kept.
          (time: base, type: 'signal_loss', value: null),
          // New instant → kept.
          (
            time: base.add(const Duration(hours: 1)),
            type: 'new_sensor',
            value: null,
          ),
        ]);

        final all = store.eventsBetween(
          base.subtract(const Duration(days: 1)),
          base.add(const Duration(days: 1)),
        );
        // The duplicate glucose_low is dropped; the same-instant signal_loss and
        // the later new_sensor are both kept → 3, not 4.
        expect(all, hasLength(3));
        expect(
          all.map((event) => event.type),
          containsAll(['glucose_low', 'signal_loss', 'new_sensor']),
        );
      },
    );
  });

  group('backend sensor sync', () {
    test(
      'id/data are keyed per sensor and the dismissed flag round-trips',
      () async {
        final store = await CgmStore.open();
        expect(store.backendSensorId('keyA'), isNull);

        await store.saveBackendSensorId('keyA', 'uuid-a');
        await store.saveBackendSyncedData('keyA', 'blob-a');
        // A different sensor key is independent → a new sensor registers afresh.
        expect(store.backendSensorId('keyA'), 'uuid-a');
        expect(store.backendSyncedData('keyA'), 'blob-a');
        expect(store.backendSensorId('keyB'), isNull);

        expect(store.restoreDismissedId, isNull);
        await store.setRestoreDismissed('uuid-a');
        expect(store.restoreDismissedId, 'uuid-a');
      },
    );

    test('sessionKeyHex round-trips the raw wire form', () async {
      final store = await CgmStore.open();
      await store.saveSessionKeyHex('keyA', 'deadbeef');
      expect(store.sessionKeyHex('keyA'), 'deadbeef');
    });
  });

  test('reload observes writes made through another isolate', () async {
    final backing = installSecureStorageMock();
    final store = await CgmStore.open();
    expect(store.loadReadings('serialA'), isEmpty);
    // Simulate the service isolate writing directly to the backing store.
    backing['g7.readings.serialA'] = '0:100,300:110';
    await store.reload();
    expect(store.loadReadings('serialA'), {0: 100, 300: 110});
  });
}
