import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/loop/loop_mode_backup.dart';
import 'package:insulink/src/pump/loop/loop_switch.dart';
import 'package:insulink/src/pump/pod_basal_delivery.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';

import '../support/secure_storage_mock.dart';
import 'fake_secure_storage.dart';

/// A controller that records the pod operations instead of opening a link.
class RecordingPodController extends PodController {
  RecordingPodController({required super.store});

  int cancelled = 0;
  bool cancelFails = false;
  int schedulesSent = 0;
  bool suspended = false;
  Duration? age = Duration.zero;

  @override
  Duration? get statusAge => age;

  @override
  bool get isSuspended => suspended;

  @override
  Future<void> applyBasalProfile(PodBasalProgram program) async {
    schedulesSent++;
    await store.saveBasalRates(PodController.hourlyRatesOf(program));
  }

  @override
  Future<void> cancelTemporaryBasal() async {
    cancelled++;
    if (cancelFails) {
      throw StateError('pod out of range');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> backing;
  late Map<String, String> platform;
  late PodStore store;
  late RecordingPodController controller;
  final now = DateTime(2026, 5, 4, 9, 30);

  setUp(() async {
    platform = installSecureStorageMock();
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
    controller = RecordingPodController(store: store);
    await store.savePairing(
      uniqueId: 0x1091,
      longTermKey: FakeSecureStorage.dummyKey,
      lotNumber: 1,
      podSequenceNumber: 1,
      activatedAt: now.subtract(const Duration(hours: 4)),
      resetSessionCounters: true,
    );
    await store.saveActivationStep('running');
    await store.saveBasalRates(List<double>.filled(24, 1.0));
  });

  group('what stops the automation being engaged', () {
    test('a ready pod blocks nothing', () async {
      expect(await LoopSwitch(controller).blockedReason(), isNull);
    });

    test('no pod', () async {
      await store.forgetPod();

      expect(await LoopSwitch(controller).blockedReason(),
          'pump.loop.blocked.no_pod');
    });

    /// The schedule is what the pod falls back to when a rate expires. Without
    /// one there is nothing to fall back to, which is the whole safety net.
    test('a pod with no basal schedule', () async {
      backing.remove('pod.basal_rates');
      await store.reload();

      expect(await LoopSwitch(controller).blockedReason(),
          'pump.loop.blocked.no_schedule');
    });

    test('limits that contradict each other', () async {
      platform[LoopLimits.keySuspendBelow] = '100';
      platform['glucose_target_low'] = '80';
      platform['glucose_target_high'] = '90';

      expect(await LoopSwitch(controller).blockedReason(),
          'pump.loop.blocked.limits');
    });

    /// Reported before the switch moves rather than after. A loop that engages
    /// and immediately stops itself teaches the user the switch does not work.
    test('a blocked engage changes nothing', () async {
      await store.forgetPod();

      final blocked = await LoopSwitch(controller).setMode(PodLoopMode.engaged);

      expect(blocked, isNotNull);
      expect(store.loopMode, PodLoopMode.off);
    });
  });

  group('switching off hands the pod back', () {
    setUp(() async {
      await store.saveLoopMode(PodLoopMode.engaged);
      await store.saveTemporaryBasal(PodTemporaryBasal(
        unitsPerHour: 2.0,
        start: now,
        end: now.add(const Duration(minutes: 30)),
        automated: true,
      ));
    });

    test('the running rate is cancelled', () async {
      await LoopSwitch(controller).setMode(PodLoopMode.off);

      expect(store.loopMode, PodLoopMode.off);
      expect(controller.cancelled, 1);
    });

    /// The mode is written BEFORE the pod is reached, so a cancel that fails
    /// still leaves an app that has stopped automating. The rate expires on its
    /// own within the fuse regardless; reaching the pod only makes the schedule
    /// resume sooner.
    test('a cancel that fails still leaves the automation off', () async {
      controller.cancelFails = true;

      await expectLater(
        LoopSwitch(controller).setMode(PodLoopMode.off),
        throwsA(isA<StateError>()),
      );

      expect(store.loopMode, PodLoopMode.off);
    });

    test('nothing is sent when no rate is running', () async {
      await store.clearTemporaryBasal();

      await LoopSwitch(controller).setMode(PodLoopMode.off);

      expect(controller.cancelled, 0);
    });

    /// The reason it stopped is about the last time it stopped ITSELF. Leaving
    /// it standing after the user has switched it back on would explain a state
    /// the app is no longer in.
    test('turning it back on clears the reason it stopped', () async {
      await store.stopLoop(PodLoopStop.podUnreachable);

      await LoopSwitch(controller).setMode(PodLoopMode.engaged);

      expect(store.loopStop, isNull);
      expect(store.loopMode, PodLoopMode.engaged);
    });
  });

  /// A restore brings back the key but not the schedule; it is sent at once, and
  /// the automation comes back only if it was on when the pod was left.
  group('a pod adopted from the account', () {
    setUp(() async {
      backing.remove('pod.basal_rates');
      await store.reload();
    });

    test('gets the schedule and is re-engaged when it was on', () async {
      platform[LoopModeBackup.key] = PodLoopMode.engaged.name;

      await LoopSwitch(controller).resumeAfterRestore();

      expect(controller.schedulesSent, 1);
      expect(store.loopMode, PodLoopMode.engaged);
    });

    test('gets the schedule but stays off when it was off', () async {
      await LoopSwitch(controller).resumeAfterRestore();

      expect(controller.schedulesSent, 1);
      expect(store.loopMode, PodLoopMode.off);
    });

    /// Programming a schedule IS resuming; a pause the user chose stays.
    test('a suspended or unread pod is left alone', () async {
      platform[LoopModeBackup.key] = PodLoopMode.engaged.name;
      controller.suspended = true;
      await LoopSwitch(controller).resumeAfterRestore();
      controller
        ..suspended = false
        ..age = null;
      await LoopSwitch(controller).resumeAfterRestore();

      expect(controller.schedulesSent, 0);
      expect(store.loopMode, PodLoopMode.off);
    });
  });

  /// Switching OFF must never be refused, whatever state the pod is in. It is
  /// the direction that stops insulin, and a check that can fail closed has no
  /// business in front of it.
  test('turning it off is never blocked', () async {
    await store.saveLoopMode(PodLoopMode.engaged);
    await store.forgetPod();
    await store.saveLoopMode(PodLoopMode.engaged);

    expect(await LoopSwitch(controller).setMode(PodLoopMode.off), isNull);
    expect(store.loopMode, PodLoopMode.off);
  });
}
