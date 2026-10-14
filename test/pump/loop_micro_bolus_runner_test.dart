import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/loop/loop_micro_bolus_settings.dart';
import 'package:insulink/src/pump/loop/loop_runner.dart';
import 'package:insulink/src/pump/pod_retry.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_temp_basal_command.dart';

import '../support/secure_storage_mock.dart';
import 'fake_secure_storage.dart';
import 'loop_input.dart';
import 'loop_runner_test.dart'
    show ScriptedConnection, ScriptedSession, statusBody;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PodStore store;
  late List<String> log;
  final clock = DateTime(2026, 5, 4, 9, 30);

  setUp(() async {
    installSecureStorageMock();
    await LoopMicroBolusSettings.enabled.save(true);
    final backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
    await store.savePairing(
      uniqueId: 0x1091,
      longTermKey: FakeSecureStorage.dummyKey,
      lotNumber: 1,
      podSequenceNumber: 1,
      activatedAt: clock.subtract(const Duration(hours: 4)),
      resetSessionCounters: true,
    );
    await store.saveActivationStep('running');
    await store.saveBasalRates(List<double>.filled(24, 1.0));
    await store.addBasalDelivery(
      at: clock.subtract(const Duration(minutes: 15)),
      units: 0,
      countedTo: clock.subtract(const Duration(minutes: 15)),
    );
    await store.markSeen(clock);
    log = <String>[];
  });

  /// A cycle on a glucose of 220 rising 2 per minute, against [session].
  Future<void> cycle(ScriptedSession session) {
    return PodLoopRunner(
      store: store,
      readGlucose: () async => glucoseAt(clock, mgdl: 220, trendPerMinute: 2),
      readMealIob: (_) async => 0,
      onLog: log.add,
      notifyStopped: (_) async {},
      connection: ScriptedConnection(store: store, session: session),
      retry: const PodRetry(attempts: 1),
      now: () => clock,
    ).tick();
  }

  ScriptedSession sessionThat({bool refusesBolus = false}) => ScriptedSession(
    statusFor: () => statusBody(),
    nakOn: (command) => refusesBolus && command is PodProgramBolusCommand,
  );

  test('the rate goes out first, then the micro bolus', () async {
    await store.saveLoopMode(PodLoopMode.engaged);
    final session = sessionThat();

    await cycle(session);

    final rate = session.commandsOfType<PodProgramTempBasalCommand>().single;
    final bolus = session.commandsOfType<PodProgramBolusCommand>().single;
    expect(session.sent.indexOf(rate), lessThan(session.sent.indexOf(bolus)));
    expect(rate.rate.unitsPerHour, 1.0);
    expect(bolus.amount.pulses * PodBolusAmount.pulseUnits, closeTo(0.5, 1e-9));
  });

  test('a given micro bolus is booked and shown', () async {
    await store.saveLoopMode(PodLoopMode.engaged);

    await cycle(sessionThat());

    expect(store.loopMicroBoluses.single.units, closeTo(0.5, 1e-9));
    expect(store.loopCycles.single.reason, LoopReason.microBolusing);
    expect(store.loopCycles.single.microBolusUnits, closeTo(0.5, 1e-9));
    expect(store.loopCycles.single.microBolusBoundBy, LoopBound.maxMicroBolus);
  });

  test('a refused micro bolus is taken back out of the books', () async {
    await store.saveLoopMode(PodLoopMode.engaged);

    await cycle(sessionThat(refusesBolus: true));

    expect(store.loopMicroBoluses, isEmpty);
    expect(store.loopCycles.single.delivered, isTrue);
    expect(store.loopCycles.single.microBolusUnits, 0);
  });

  test('off writes the micro bolus down without giving it', () async {
    await store.saveLastStatus(PodStatusResponse(statusBody()), clock);
    final session = sessionThat();

    await cycle(session);

    expect(session.sent, isEmpty);
    expect(store.loopMicroBoluses, isEmpty);
    expect(store.loopCycles.single.delivered, isFalse);
    expect(store.loopCycles.single.microBolusUnits, greaterThan(0));
  });
}
