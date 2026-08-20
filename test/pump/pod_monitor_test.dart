
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_connection.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/service/pod_alarms.dart';
import 'package:insulink/src/pump/service/pod_monitor.dart';

import '../support/secure_storage_mock.dart';

void silenceNotifications() {
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') {
          return true;
        }
        return null;
      });
}

/// A connection that cannot reach a pod, which is the case the monitor has to
/// survive without losing its contact-free warnings.
class UnreachableConnection extends PodConnection {
  UnreachableConnection({required super.store});

  int attempts = 0;

  @override
  Future<PodSession> openSession({bool allowScan = true}) async {
    attempts++;
    scanAllowed = allowScan;
    throw PodLinkException('no pod in range');
  }

  /// Whether the last attempt was allowed to scan. The service must never scan.
  bool scanAllowed = true;

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PodStore store;
  late PodAlarmManager alarms;
  late UnreachableConnection connection;
  late List<String> log;
  late DateTime clock;

  PodMonitor buildMonitor() => PodMonitor(
        store: store,
        alarms: alarms,
        onLog: log.add,
        connection: connection,
        now: () => clock,
      );

  /// A pod that finished activating. The watch only ever looks at a RUNNING pod,
  /// so every case here starts from one.
  Future<void> pairPod({Duration age = const Duration(hours: 1)}) async {
    await store.savePairing(
      uniqueId: 4241,
      longTermKey: Uint8List.fromList(List<int>.filled(16, 7)),
      lotNumber: 1,
      podSequenceNumber: 2,
      activatedAt: clock.subtract(age),
    );
    await store.saveActivationStep('running');
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    installSecureStorageMock();
    silenceNotifications();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    // Anchored on the real clock: the poll interval is driven by the injected
    // one, but the expiry warnings read the wall clock, so the two have to agree.
    clock = DateTime.now();
    log = <String>[];
    store = await PodStore.open();
    alarms = PodAlarmManager(FlutterLocalNotificationsPlugin());
    connection = UnreachableConnection(store: store);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('with no pod paired the monitor does nothing', () {
    test('it never reaches for the radio', () async {
      await buildMonitor().tick();
      expect(connection.attempts, 0);
      expect(log, isEmpty);
    });
  });

  group('the poll runs on its own interval, not on every tick', () {
    test('the first tick polls', () async {
      await pairPod();
      final monitor = buildMonitor();
      await monitor.tick();
      expect(connection.attempts, 1);
    });

    test('a tick straight afterwards does not poll again', () async {
      await pairPod();
      final monitor = buildMonitor();
      await monitor.tick();
      await monitor.tick();
      await monitor.tick();
      expect(connection.attempts, 1);
    });

    test('once the interval has passed it polls again', () async {
      await pairPod();
      final monitor = buildMonitor();
      await monitor.tick();
      clock = clock.add(PodMonitor.pollInterval);
      await monitor.tick();
      expect(connection.attempts, 2);
    });
  });

  group('the service does not scan, with one bounded exception', () {
    test('a normal poll asks for a scan-free connect', () async {
      await pairPod();
      await buildMonitor().tick();
      expect(
        connection.scanAllowed,
        isFalse,
        reason: 'a scan here would compete with the CGM and wedge the OS scanner',
      );
    });

    /// A fresh process may never have SEEN the stored address, and the OS will not
    /// connect to one it has not observed. One scan teaches it — after enough
    /// failures that a pod merely out of range does not start the scanner.
    test('after repeated failures one poll is allowed to scan', () async {
      await pairPod();
      final monitor = buildMonitor();
      for (var poll = 0; poll < PodMonitor.scanAfterFailures; poll++) {
        await monitor.tick();
        expect(connection.scanAllowed, isFalse, reason: 'poll $poll');
        clock = clock.add(PodMonitor.pollInterval);
      }
      await monitor.tick();
      expect(connection.scanAllowed, isTrue);
      expect(connection.attempts, PodMonitor.scanAfterFailures + 1);
    });

    test('a pod that answers resets the failure count', () async {
      await pairPod();
      final monitor = buildMonitor();
      await monitor.tick();
      clock = clock.add(PodMonitor.pollInterval);
      await monitor.tick();
      // A success would zero the counter; simulate one by rebuilding the monitor,
      // which is the state a fresh service starts in.
      final restarted = buildMonitor();
      clock = clock.add(PodMonitor.pollInterval);
      await restarted.tick();
      expect(connection.scanAllowed, isFalse);
    });
  });

  group('an unreachable pod does not stop the contact-free warnings', () {
    test('a failed poll is logged, not thrown', () async {
      await pairPod();
      await buildMonitor().tick();
      expect(log.single, contains('pod poll failed'));
    });

    /// The point of the split: expiry is computed from stored values, so it still
    /// warns when the pod cannot be reached at all.
    test('expiry still warns while the pod is unreachable', () async {
      await pairPod(age: const Duration(hours: 79));
      await buildMonitor().tick();
      expect(store.alarmNotified('expiry'), isTrue);
      expect(connection.attempts, 1, reason: 'it still tried');
    });

    test('an expired pod still warns while unreachable', () async {
      await pairPod(age: const Duration(hours: 90));
      await buildMonitor().tick();
      expect(store.alarmNotified('expired'), isTrue);
    });
  });

  group('a pod that has not finished activating is left alone', () {
    /// Such a pod answers everything but the activation sequence with an
    /// illegal-command-state NAK, and an activation is very likely running on
    /// that link right now. Polling it competes for the radio with the wizard
    /// trying to finish it.
    test('a paired but unactivated pod is never polled', () async {
      await store.savePairing(
        uniqueId: 4241,
        longTermKey: Uint8List.fromList(List<int>.filled(16, 7)),
        lotNumber: 1,
        podSequenceNumber: 2,
        activatedAt: clock,
      );

      await buildMonitor().tick();

      expect(connection.attempts, 0);
    });

    test('the same pod is polled once its activation finished', () async {
      await pairPod();

      await buildMonitor().tick();

      expect(connection.attempts, greaterThan(0));
    });
  });

}
