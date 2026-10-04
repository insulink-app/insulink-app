import 'package:flutter_test/flutter_test.dart';
import 'dart:math';

import 'package:insulink/src/demo/demo_glucose.dart';
import 'package:insulink/src/demo/demo_pump.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:insulink/src/pump/pod_basal_adapter.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the demo pod runs the active profile with every past hour booked',
    () async {
      installSecureStorageMock();
      final now = DateTime(2026, 10, 4, 12, 30);
      await DemoPump(now, const {}).attach();

      final store = await PodStore.open();
      final controller = PodController(store: store);
      final profile = (await ProfileBasalState.load()).active;
      expect(store.isActivated, isTrue);
      expect(
        controller.runsDifferentBasalThan(PodBasalAdapter(profile).program),
        isFalse,
      );
      expect(store.basalHours, hasLength(45));
      expect(store.basalHours.last.hour, DateTime(2026, 10, 4, 11));
      expect(
        store.lastStatus!.reservoirPulsesRemaining,
        DemoPump.reservoirPulses,
      );
    },
  );

  test('automated delivery is on, with cycles the loop decided', () async {
    installSecureStorageMock();
    final now = DateTime(2026, 10, 4, 12, 30);
    final glucose = DemoGlucose(now: now, random: Random(2026));
    await DemoPump(now, glucose.readings).attach();

    final store = await PodStore.open();
    expect(store.loopMode, PodLoopMode.engaged);
    expect(store.loopCycles, hasLength(24));
    expect(store.loopCycles.first.at, now);
    expect(store.loopCycles.first.mgdl, isNotNull);
  });
}
