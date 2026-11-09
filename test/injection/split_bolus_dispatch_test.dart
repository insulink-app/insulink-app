import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/bolus_dispatcher.dart';
import 'package:insulink/src/injection/bolus_delivery.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/nutrition/meal/meal_store.dart';
import 'package:insulink/src/pump/pod_running_bolus.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/split_bolus.dart';

import '../pump/bolus_delivery_test.dart' show ScriptedPodController, hex;
import '../pump/fake_secure_storage.dart';
import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PodStore store;
  late ScriptedPodController controller;
  late BolusDispatcher dispatcher;
  final plan = SplitBolusPlan.spread(
    20,
    over: const Duration(minutes: 30),
    from: DateTime.now(),
    mealKey: 1,
  );

  setUp(() async {
    installSecureStorageMock();
    final backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
    await store.savePairing(
      uniqueId: 4242,
      longTermKey: hex('00112233445566778899aabbccddeeff'),
      lotNumber: 1,
      podSequenceNumber: 2,
      activatedAt: DateTime.now(),
    );
    controller = ScriptedPodController(
      store: store,
      reply: (_) => throw Exception('link down'),
    );
    dispatcher = BolusDispatcher(
      controller: controller,
      meals: MealState(const MealStore(), []),
    );
  });

  Future<void> submit({required bool opensSplit}) async {
    dispatcher.submit(
      delivery: BolusDelivery(
        controller: controller,
        maxBolusUnits: 10,
        maxUnitsPerHour: 10,
      ),
      units: 1,
      deliveredLastHour: 0,
      meal: Meal(
        time: DateTime.now(),
        carbs: 20,
        glucoseMgdl: 120,
        bolus: 0,
        entries: const [],
      ),
      opensSplit: opensSplit,
    );
    while (dispatcher.isSending) {
      await pumpEventQueue();
    }
  }

  test('a failed first part drops the planned rest', () async {
    await store.saveSplitBolus(plan);

    await submit(opensSplit: true);

    expect(dispatcher.failure, isNotNull);
    expect(store.splitBolus, isNull);
  });

  test('a failed ordinary bolus leaves a running split alone', () async {
    await store.saveSplitBolus(plan);

    await submit(opensSplit: false);

    expect(dispatcher.failure, isNotNull);
    expect(store.splitBolus, isNotNull);
  });

  test('a part the service is sending is not resolved as stranded', () async {
    await store.saveSplitBolus(plan.sendingAt(DateTime.now()));
    await store.startPendingBolus(
      PodRunningBolus(
        startedAt: DateTime.now(),
        pulses: 10,
        eighthSecondsBetweenPulses: 16,
      ),
    );

    await dispatcher.resolveStranded();

    expect(store.pendingBolus, isNotNull);
    expect(dispatcher.failure, isNull);
  });
}
