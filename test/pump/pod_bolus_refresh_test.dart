import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_running_bolus.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';

import 'fake_secure_storage.dart';

/// A controller that counts its re-reads instead of opening a radio link.
class CountingPodController extends PodController {
  CountingPodController({required super.store});

  int reads = 0;

  @override
  Future<void> refresh() async {
    reads++;
  }
}

void main() {
  testWidgets('the pod is read again once the running bolus has finished', (
    tester,
  ) async {
    final backing = <String, String>{};
    final store = PodStore(FakeSecureStorage(backing), backing);
    final controller = CountingPodController(store: store);
    await store.startRunningBolus(
      PodRunningBolus(
        startedAt: DateTime.now(),
        pulses: 20,
        eighthSecondsBetweenPulses:
            PodProgramBolusCommand.defaultEighthSecondsBetweenPulses,
      ),
    );

    controller.notifyRunningBolusChanged();
    await tester.pump(const Duration(seconds: 30));
    expect(controller.reads, 0, reason: 'the bolus is still running');

    await tester.pump(const Duration(seconds: 20));
    expect(controller.reads, 1, reason: 'the reservoir has changed by now');

    controller.dispose();
  });
}
