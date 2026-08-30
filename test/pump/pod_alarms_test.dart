
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_alarm.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/service/pod_alarms.dart';

import '../support/secure_storage_mock.dart';

/// Records every notification the alarm manager posts or clears, so the
/// decisions can be exercised without a device.
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

Uint8List statusBody({
  PodLifecycleStatus lifecycle = PodLifecycleStatus.runningAboveMinimumVolume,
  PodDeliveryStatus delivery = PodDeliveryStatus.basalActive,
  int reservoirPulses = 0x3FF,
}) {
  final body = Uint8List(10);
  body[0] = 0x1d;
  body[1] = (delivery.value << 4) | lifecycle.value;
  ByteData.view(body.buffer)
    ..setUint32(2, 0)
    ..setUint32(6, reservoirPulses & 0x3FF);
  return body;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ({List<int> shown, List<int> cancelled}) notifications;
  late PodAlarmManager alarms;
  late PodStore store;

  // The ids PodAlarmManager posts under, mirrored here so a renumbering that
  // collided with the CGM manager's 0-104 would fail loudly.
  const expiryId = 110;
  const expiredId = 111;
  const reservoirId = 112;
  const alarmId = 113;
  const unreachableId = 114;
  const stoppedId = 115;

  Future<void> pairPod({Duration age = const Duration(hours: 1)}) =>
      store.savePairing(
        uniqueId: 4241,
        longTermKey: Uint8List.fromList(List<int>.filled(16, 7)),
        lotNumber: 1,
        podSequenceNumber: 2,
        activatedAt: DateTime.now().subtract(age),
      );

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    installSecureStorageMock();
    notifications = installNotificationMock();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    alarms = PodAlarmManager(FlutterLocalNotificationsPlugin());
    store = await PodStore.open();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('expiry warns without needing to reach the pod', () {
    test('a fresh pod warns about nothing', () async {
      await pairPod();
      await alarms.checkExpiry(store);
      expect(notifications.shown, isEmpty);
    });

    test('inside the configured window it warns once', () async {
      await pairPod(age: const Duration(hours: 77));
      await alarms.checkExpiry(store);
      expect(notifications.shown, [expiryId]);

      await alarms.checkExpiry(store);
      expect(notifications.shown, [expiryId], reason: 'must not repeat');
    });

    test('an expired pod gets its own warning', () async {
      await pairPod(age: const Duration(hours: 81));
      await alarms.checkExpiry(store);
      expect(notifications.shown, [expiredId]);
    });

    test('a new pod warns again', () async {
      await pairPod(age: const Duration(hours: 77));
      await alarms.checkExpiry(store);
      notifications.shown.clear();

      // A different activation time is a different pod.
      await pairPod(age: const Duration(hours: 78));
      await alarms.checkExpiry(store);
      expect(notifications.shown, [expiryId]);
    });

    test('switched off, it stays quiet — and can still fire once switched on',
        () async {
      await pairPod(age: const Duration(hours: 77));
      await NotificationSetting.podExpiry.save(false);
      await alarms.checkExpiry(store);
      expect(notifications.shown, isEmpty);

      await NotificationSetting.podExpiry.save(true);
      await alarms.checkExpiry(store);
      expect(notifications.shown, [expiryId]);
    });

    test('nothing fires without a pod', () async {
      await alarms.checkExpiry(store);
      expect(notifications.shown, isEmpty);
    });
  });

  group('reservoir', () {
    test('a reservoir the pod cannot measure warns about nothing', () async {
      await pairPod();
      await alarms.checkReservoir(store, PodStatusResponse(statusBody()));
      expect(notifications.shown, isEmpty);
    });

    test('below the threshold it warns once', () async {
      await pairPod();
      // 100 pulses = 5.0 U, under the 10 U default.
      final low = PodStatusResponse(statusBody(reservoirPulses: 100));
      await alarms.checkReservoir(store, low);
      expect(notifications.shown, [reservoirId]);

      await alarms.checkReservoir(store, low);
      expect(notifications.shown, [reservoirId]);
    });

    test('comfortably above the threshold stays quiet', () async {
      await pairPod();
      // 600 pulses = 30 U.
      await alarms.checkReservoir(
        store,
        PodStatusResponse(statusBody(reservoirPulses: 600)),
      );
      expect(notifications.shown, isEmpty);
    });
  });

  group('a pod alarm is reported on the edge and never opted out of', () {
    test('an occlusion is reported', () async {
      await alarms.checkAlarm(const PodAlarm(0x14));
      expect(notifications.shown, [alarmId]);
    });

    test('the same standing alarm is not repeated', () async {
      await alarms.checkAlarm(const PodAlarm(0x14));
      await alarms.checkAlarm(const PodAlarm(0x14));
      expect(notifications.shown, [alarmId]);
    });

    test('a different kind of alarm is reported again', () async {
      await alarms.checkAlarm(const PodAlarm(0x14));
      await alarms.checkAlarm(const PodAlarm(0x18));
      expect(notifications.shown, [alarmId, alarmId]);
    });

    test('a pod reporting itself clear clears the notification', () async {
      await alarms.checkAlarm(const PodAlarm(0x14));
      await alarms.checkAlarm(const PodAlarm(0x00));
      expect(notifications.cancelled, contains(alarmId));
    });

    /// Delivery having stopped is not something to be silent about, so the
    /// preference and silent mode do not gate it.
    test('it fires even with the warnings switched off', () async {
      await NotificationSetting.podExpiry.save(false);
      await NotificationSetting.podInsulin.save(false);
      await alarms.checkAlarm(const PodAlarm(0x14));
      expect(notifications.shown, [alarmId]);
    });
  });

  group('a pod that stopped on its own', () {
    PodStatusResponse suspended() => PodStatusResponse(statusBody(
          delivery: PodDeliveryStatus.suspended,
        ));

    test('is reported', () async {
      await pairPod();
      await alarms.checkDelivering(store, PodStatusResponse(statusBody()));
      await alarms.checkDelivering(store, suspended());
      expect(notifications.shown, [stoppedId]);
    });

    /// After a deliberate suspend the pod does not report delivering again, so the
    /// suspended status is the first one seen. That is also the case a restarted
    /// service lands in, where the edge tracker starts out assuming delivery.
    test('is not reported when we stopped it ourselves', () async {
      await pairPod();
      await store.setSuspendedByUs(true);
      await alarms.checkDelivering(store, suspended());
      expect(notifications.shown, isEmpty);
    });

    test('a restarted service does not mistake our suspend for a fault', () async {
      await pairPod();
      await store.setSuspendedByUs(true);
      // A fresh manager, as after a service restart: it assumes delivery until
      // told otherwise, and the stored flag is what keeps it quiet.
      final restarted = PodAlarmManager(FlutterLocalNotificationsPlugin());
      await restarted.checkDelivering(store, suspended());
      expect(notifications.shown, isEmpty);
    });

    test('delivering again clears both the notice and the flag', () async {
      await pairPod();
      await store.setSuspendedByUs(true);
      await alarms.checkDelivering(store, PodStatusResponse(statusBody()));
      expect(store.suspendedByUs, isFalse);
      expect(notifications.cancelled, contains(stoppedId));
    });

    test('a deactivated pod is not reported as having stopped', () async {
      await pairPod();
      await alarms.checkDelivering(store, PodStatusResponse(statusBody()));
      await alarms.checkDelivering(
        store,
        PodStatusResponse(statusBody(
          lifecycle: PodLifecycleStatus.deactivated,
          delivery: PodDeliveryStatus.suspended,
        )),
      );
      expect(notifications.shown, isEmpty);
    });
  });

  group('losing contact is itself a warning', () {
    test('a recently seen pod warns about nothing', () async {
      await pairPod();
      await store.markSeen(DateTime.now());
      await alarms.checkReachable(store);
      expect(notifications.shown, isEmpty);
      expect(notifications.cancelled, contains(unreachableId));
    });

    test('a long silence is reported', () async {
      await pairPod();
      await store.markSeen(
        DateTime.now().subtract(PodAlarmManager.unreachableAfter * 2),
      );
      await alarms.checkReachable(store);
      expect(notifications.shown, [unreachableId]);
    });

    /// The reported spamming: the check runs every thirty seconds, and it used
    /// to post its notification on each of them. Swiping it away brought it
    /// straight back, alerting again, for as long as the pod was out of range.
    test('a standing silence is said once, not on every tick', () async {
      await pairPod();
      await store.markSeen(
        DateTime.now().subtract(PodAlarmManager.unreachableAfter * 2),
      );

      for (var tick = 0; tick < 10; tick++) {
        await alarms.checkReachable(store);
      }

      expect(notifications.shown, [unreachableId]);
    });

    /// The gate is per episode, not for the life of the pod: a link that comes
    /// back and drops again is a new thing to say.
    test('the pod answering again re-arms the warning', () async {
      await pairPod();
      await store.markSeen(
        DateTime.now().subtract(PodAlarmManager.unreachableAfter * 2),
      );
      await alarms.checkReachable(store);

      await store.markSeen(DateTime.now());
      await alarms.checkReachable(store);
      await store.markSeen(
        DateTime.now().subtract(PodAlarmManager.unreachableAfter * 2),
      );
      await alarms.checkReachable(store);

      expect(notifications.shown, [unreachableId, unreachableId]);
    });

    test('a pod never contacted is not reported as lost', () async {
      await pairPod();
      await alarms.checkReachable(store);
      expect(notifications.shown, isEmpty);
    });
  });

  group('notification ids', () {
    test('stay clear of the CGM manager range', () {
      for (final id in [expiryId, expiredId, reservoirId, alarmId, unreachableId, stoppedId]) {
        expect(id, greaterThan(104));
      }
      expect(
        {expiryId, expiredId, reservoirId, alarmId, unreachableId, stoppedId},
        hasLength(6),
        reason: 'ids must be distinct or one warning replaces another',
      );
    });
  });
}
