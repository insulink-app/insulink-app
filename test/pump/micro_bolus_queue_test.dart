import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/bolus_delivery.dart';
import 'package:insulink/src/injection/micro_bolus_queue.dart';
import 'package:insulink/src/pump/pod_running_bolus.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

import '../support/secure_storage_mock.dart';
import 'bolus_delivery_test.dart' show ScriptedPodController, hex, statusBody;
import 'fake_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PodStore store;
  late Map<String, String> settings;
  late List<Duration> slept;
  late ScriptedPodController controller;

  setUp(() async {
    settings = installSecureStorageMock();
    final backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
    await store.savePairing(
      uniqueId: 4242,
      longTermKey: hex('00112233445566778899aabbccddeeff'),
      lotNumber: 1,
      podSequenceNumber: 2,
      activatedAt: DateTime.now(),
    );
    slept = <Duration>[];
    controller = ScriptedPodController(
      store: store,
      reply: (amount) => PodStatusResponse(
        statusBody(
          delivery: PodDeliveryStatus.bolusAndBasalActive,
          bolusPulsesRemaining: amount.pulses,
        ),
      ),
    );
  });

  /// A bolus that started [ago] and runs for [pulses] pulses at 2 s each.
  Future<void> running({
    required Duration ago,
    required int pulses,
    bool automated = true,
  }) {
    return store.startRunningBolus(
      PodRunningBolus(
        startedAt: DateTime.now().subtract(ago),
        pulses: pulses,
        eighthSecondsBetweenPulses:
            PodProgramBolusCommand.defaultEighthSecondsBetweenPulses,
        automated: automated,
      ),
    );
  }

  BolusDelivery delivery() => BolusDelivery(
    controller: controller,
    maxBolusUnits: 10,
    maxUnitsPerHour: 15,
    queue: MicroBolusQueue(
      sleep: (duration) async {
        slept.add(duration);
        expect(
          store.pendingBolus,
          isNull,
          reason: 'a dose still waiting must not look sent',
        );
      },
    ),
  );

  test('with nothing running the bolus goes out at once', () async {
    final outcome = await delivery().deliver(2.0, deliveredLastHour: 0);

    expect(outcome.isDelivered, isTrue);
    expect(slept, isEmpty);
  });

  /// 0.5 U is 20 s; 5 s in, 15 s are left plus the settle time.
  test('a micro bolus inside the limit is waited out, then sent', () async {
    await running(ago: const Duration(seconds: 5), pulses: 10);

    final outcome = await delivery().deliver(2.0, deliveredLastHour: 0);

    expect(outcome.isDelivered, isTrue);
    expect(controller.sent.single.units, 2.0);
    expect(slept.single.inSeconds, inInclusiveRange(17, 18));
  });

  /// 3 U is 120 s, past the default 60 s: refused with the time left, at once.
  test('a micro bolus past the limit refuses and says how long', () async {
    await running(ago: Duration.zero, pulses: 60);

    final outcome = await delivery().deliver(2.0, deliveredLastHour: 0);

    expect(outcome.status, BolusDeliveryStatus.refused);
    expect(outcome.detailKey, 'pump.bolus.queue_too_long');
    expect(int.parse(outcome.detailParam!), inInclusiveRange(118, 120));
    expect(controller.sent, isEmpty);
    expect(slept, isEmpty);
  });

  test('the limit is the user setting', () async {
    settings['loop_micro_bolus_queue_seconds'] = '180';
    await running(ago: Duration.zero, pulses: 60);

    final outcome = await delivery().deliver(2.0, deliveredLastHour: 0);

    expect(outcome.isDelivered, isTrue);
    expect(slept, hasLength(1));
  });

  /// A manual bolus still running means the user tapped twice. Queueing it
  /// would be a second dose, so it is refused, in the user's language.
  test('a manual bolus is never queued behind', () async {
    await running(ago: Duration.zero, pulses: 40, automated: false);
    controller = ScriptedPodController(
      store: store,
      reply: (amount) => PodStatusResponse(statusBody()),
      initialStatus: statusBody(
        delivery: PodDeliveryStatus.bolusAndBasalActive,
        bolusPulsesRemaining: 40,
      ),
    );

    final outcome = await delivery().deliver(2.0, deliveredLastHour: 0);

    expect(outcome.status, BolusDeliveryStatus.refused);
    expect(outcome.detailKey, 'pump.bolus.already_running');
    expect(slept, isEmpty);
  });

  test('a finished micro bolus is not waited for', () async {
    await running(ago: const Duration(minutes: 2), pulses: 10);

    await delivery().deliver(2.0, deliveredLastHour: 0);

    expect(slept, isEmpty);
  });
}
