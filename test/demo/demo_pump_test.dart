import 'package:flutter_test/flutter_test.dart';
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
      await DemoPump(now).attach();

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
}
