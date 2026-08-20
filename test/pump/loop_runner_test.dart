import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/loop/loop_glucose.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/loop/loop_runner.dart';
import 'package:insulink/src/pump/pod_basal_delivery.dart';
import 'package:insulink/src/pump/pod_connection.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_control_commands.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_ids.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';
import 'package:insulink/src/pump/protocol/pod_message_io.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/protocol/pod_session_keys.dart';
import 'package:insulink/src/pump/protocol/pod_stop_delivery_command.dart';
import 'package:insulink/src/pump/protocol/pod_temp_basal_command.dart';
import 'package:insulink/src/pump/protocol/session_cipher.dart';

import '../support/secure_storage_mock.dart';
import 'fake_pod.dart';
import 'fake_secure_storage.dart';
import 'loop_input.dart';

/// A pod status body built to order.
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

/// A session that records every command instead of putting it on a radio.
class ScriptedSession extends PodSession {
  ScriptedSession({required this.statusFor, this.nakOn})
      : super(
          messageIo: PodMessageIo(FakePodLink(onMessage: (_) async => null)),
          addresses: PodAddressPair(podUniqueId: 0x1091),
          keys: PodSessionKeys(
            confidentialityKey: Uint8List(16),
            nonce: SessionNonce(prefix: Uint8List(8), sequence: 0),
            messageSequence: 0,
            eapSequence: 2,
          ),
        );

  final Uint8List Function() statusFor;

  /// A command type the pod refuses, so the refusal path can be exercised.
  final bool Function(PodCommand command)? nakOn;

  final List<PodCommand> sent = <PodCommand>[];

  @override
  Future<PodResponse> run(PodCommand command) async {
    sent.add(command);
    if (nakOn != null && nakOn!(command)) {
      return PodNakResponse(hex('0603070008'));
    }
    return PodStatusResponse(statusFor());
  }

  List<T> commandsOfType<T>() => sent.whereType<T>().toList();
}

/// A connection that hands out [session] instead of opening a link, or throws
/// when the pod is meant to be out of reach.
class ScriptedConnection extends PodConnection {
  ScriptedConnection({required super.store, required this.session});

  final ScriptedSession session;
  bool reachable = true;
  int opened = 0;
  bool scanAsked = false;

  @override
  Future<PodSession> openSession({bool allowScan = true}) async {
    opened++;
    scanAsked = allowScan;
    if (!reachable) {
      throw PodLinkException('no pod in range');
    }
    return session;
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> backing;
  late PodStore store;
  late ScriptedSession session;
  late ScriptedConnection connection;
  late List<String> log;
  late List<PodLoopStop> announced;
  late DateTime clock;

  var delivery = PodDeliveryStatus.basalActive;

  setUp(() async {
    installSecureStorageMock();
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
    clock = DateTime(2026, 5, 4, 9, 30);
    delivery = PodDeliveryStatus.basalActive;
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
    session = ScriptedSession(statusFor: () => statusBody(delivery: delivery));
    connection = ScriptedConnection(store: store, session: session);
    log = <String>[];
    announced = <PodLoopStop>[];
  });

  PodLoopRunner runnerWith({
    LoopGlucose? glucose,
    double mealIob = 0,
  }) {
    return PodLoopRunner(
      store: store,
      readGlucose: () async => glucose ?? glucoseAt(clock, mgdl: 220),
      readMealIob: (_) async => mealIob,
      onLog: log.add,
      notifyStopped: (cause) async => announced.add(cause),
      connection: connection,
      now: () => clock,
    );
  }

  group('the switch decides whether anything reaches the pod', () {
    test('nothing happens while the automation is off', () async {
      await runnerWith().tick();

      expect(connection.opened, 0);
      expect(store.loopCycles, isEmpty);
    });

    /// Observation is how a loop is watched against a real day before it is
    /// trusted. It has to read the pod to decide anything, but it must never
    /// program it.
    test('observing records a decision and programs nothing', () async {
      await store.saveLoopMode(PodLoopMode.observing);

      await runnerWith().tick();

      expect(session.commandsOfType<PodProgramTempBasalCommand>(), isEmpty);
      expect(store.loopCycles, hasLength(1));
      expect(store.loopCycles.single.delivered, isFalse);
      expect(store.loopCycles.single.unitsPerHour, greaterThan(1.0));
    });

    test('engaged programs the rate it decided on', () async {
      await store.saveLoopMode(PodLoopMode.engaged);

      await runnerWith().tick();

      final programmed = session.commandsOfType<PodProgramTempBasalCommand>();
      expect(programmed, hasLength(1));
      expect(programmed.single.rate.minutes, LoopLimits.fuse.inMinutes);
      expect(store.loopCycles.single.delivered, isTrue);
    });

    /// Never scan. A second scanner around the clock wedges the Android BLE
    /// scanner, which is what the whole pod watch is built around avoiding.
    test('the loop never starts a scan', () async {
      await store.saveLoopMode(PodLoopMode.engaged);

      await runnerWith().tick();

      expect(connection.scanAsked, isFalse);
    });
  });

  group('every programmed rate carries its own expiry', () {
    test('the temporary rate lasts exactly one fuse', () async {
      await store.saveLoopMode(PodLoopMode.engaged);

      await runnerWith().tick();

      final running = store.temporaryBasal!;
      expect(running.end.difference(running.start), LoopLimits.fuse);
    });

    /// Cancel first, and only when the pod says one is running. It orders the
    /// failure modes the right way round: a cancel that lands followed by a
    /// program that does not leaves the pod on the user's own schedule.
    test('a running temporary rate is cancelled before the new one', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      delivery = PodDeliveryStatus.tempBasalActive;

      await runnerWith().tick();

      expect(session.sent.first, isA<PodGetStatusCommand>());
      expect(session.sent[1], isA<PodStopDeliveryCommand>());
      expect(session.sent[2], isA<PodProgramTempBasalCommand>());
    });

    test('no cancel is sent when the pod is not running one', () async {
      await store.saveLoopMode(PodLoopMode.engaged);

      await runnerWith().tick();

      expect(session.commandsOfType<PodStopDeliveryCommand>(), isEmpty);
    });
  });

  group('basal is booked before the rate that delivered it is replaced', () {
    /// The store holds one temporary rate at a time. Replacing it with the
    /// window still open would bill the stretch that has passed at the NEW rate,
    /// so an automated log would describe insulin that was never given.
    test('the passed window is billed before the new rate is stored', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      await store.saveTemporaryBasal(PodTemporaryBasal(
        unitsPerHour: 3.0,
        start: clock.subtract(const Duration(minutes: 15)),
        end: clock.add(const Duration(minutes: 15)),
      ));

      await runnerWith().tick();

      final booked = store.pendingBasalDeliveries;
      expect(booked, hasLength(1));
      expect(booked.single['units'], closeTo(3.0 * 15 / 60, 1e-6));
    });

    test('the accounting mark moves to now', () async {
      await store.saveLoopMode(PodLoopMode.engaged);

      await runnerWith().tick();

      expect(store.basalCountedTo, clock);
    });
  });

  group('losing the sensor is not the same as losing the pod', () {
    /// A sensor gap is ordinary and short. The pod goes back to the user's own
    /// schedule and the automation stays on, ready for the next reading.
    test('unusable glucose reverts the pod but keeps the mode', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      delivery = PodDeliveryStatus.tempBasalActive;
      final stale = LoopGlucose.from(
        archiveEndingAt(clock.subtract(const Duration(hours: 2)), mgdl: 220),
        now: clock,
      );

      await runnerWith(glucose: stale).tick();

      expect(session.commandsOfType<PodStopDeliveryCommand>(), hasLength(1));
      expect(session.commandsOfType<PodProgramTempBasalCommand>(), isEmpty);
      expect(store.loopMode, PodLoopMode.engaged);
      expect(store.loopCycles.single.reason, LoopReason.noGlucose);
    });

    test('a sensor gap with no temporary rate running sends nothing', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      final stale = LoopGlucose.from(
        archiveEndingAt(clock.subtract(const Duration(hours: 2)), mgdl: 220),
        now: clock,
      );

      await runnerWith(glucose: stale).tick();

      expect(session.commandsOfType<PodStopDeliveryCommand>(), isEmpty);
    });
  });

  /// A clock moved backwards, by daylight saving or by flying west, leaves the
  /// recent cycles dated in the future. Every window then measures negative, the
  /// automation's own insulin bills as nothing, and the insulin-on-board it
  /// decides from is understated by whatever it has just given. That is the one
  /// accounting error that lets the next cycle add more.
  group('a clock that moved backwards is not decided on', () {
    setUp(() async {
      await store.saveLoopMode(PodLoopMode.engaged);
      await store.recordLoopCycle(PodLoopCycle(
        at: clock.add(const Duration(hours: 2)),
        unitsPerHour: 3.0,
        scheduledUnitsPerHour: 1.0,
        reason: LoopReason.correcting,
        delivered: true,
      ));
    });

    test('nothing is programmed', () async {
      await runnerWith().tick();

      expect(session.commandsOfType<PodProgramTempBasalCommand>(), isEmpty);
      expect(store.loopCycles.first.reason, LoopReason.clockUnreliable);
    });

    test('the pod is put back on its own schedule', () async {
      delivery = PodDeliveryStatus.tempBasalActive;

      await runnerWith().tick();

      expect(session.commandsOfType<PodStopDeliveryCommand>(), hasLength(1));
    });

    /// It costs at most the hour or the timezone that was skipped, so the
    /// automation waits rather than switching itself off.
    test('the automation stays on', () async {
      await runnerWith().tick();

      expect(store.loopMode, PodLoopMode.engaged);
    });

    test('a journal that is not ahead decides normally', () async {
      backing.remove('pod.loop_cycles');
      await store.reload();

      await runnerWith().tick();

      expect(session.commandsOfType<PodProgramTempBasalCommand>(), hasLength(1));
    });
  });

  group('a pod that refuses is not a pod that delivered', () {
    /// The pod answers a command it will not run with a NAK, which arrives as an
    /// ordinary response rather than an exception. Recording that as delivered
    /// would have the ledger and the insulin-on-board claim a rate that never ran.
    test('a refused rate is not recorded as delivered', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      session = ScriptedSession(
        statusFor: () => statusBody(),
        nakOn: (command) => command is PodProgramTempBasalCommand,
      );
      connection = ScriptedConnection(store: store, session: session);

      await runnerWith().tick();

      expect(store.loopCycles, hasLength(1));
      expect(store.loopCycles.single.delivered, isFalse);
    });

    /// A refused command leaves the pod on whatever it was running, so a stored
    /// stretch describing the refused rate would be a rate that does not exist.
    test('a refused rate is rolled back out of the store', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      session = ScriptedSession(
        statusFor: () => statusBody(),
        nakOn: (command) => command is PodProgramTempBasalCommand,
      );
      connection = ScriptedConnection(store: store, session: session);

      await runnerWith().tick();

      expect(store.temporaryBasal, isNull);
    });

    test('a refused suspension leaves no claim that delivery stopped', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      final userRate = PodTemporaryBasal(
        unitsPerHour: 2.0,
        start: clock.subtract(const Duration(minutes: 5)),
        end: clock.add(const Duration(minutes: 25)),
        automated: true,
      );
      await store.saveTemporaryBasal(userRate);
      session = ScriptedSession(
        statusFor: () => statusBody(delivery: PodDeliveryStatus.tempBasalActive),
        nakOn: (command) => command is PodProgramTempBasalCommand,
      );
      connection = ScriptedConnection(store: store, session: session);

      await runnerWith(glucose: glucoseAt(clock, mgdl: 70)).tick();

      expect(store.loopCycles.single.reason, LoopReason.suspendedLow);
      expect(store.loopCycles.single.delivered, isFalse);
      expect(store.temporaryBasal!.covers(clock), isFalse);
    });
  });

  /// A bolus whose outcome nobody could confirm may be in the body. The loop
  /// computes what it may add from what is already on board, so a loop blind to
  /// that dose would add on top of it.
  test('a bolus of unknown outcome holds the rate down', () async {
    await store.saveLoopMode(PodLoopMode.engaged);
    await store.recordUnconfirmedBolus(PodDelivery(
      at: clock.subtract(const Duration(minutes: 5)),
      units: 6.0,
      kind: PodDeliveryKind.bolus,
    ));

    await runnerWith(glucose: glucoseAt(clock, mgdl: 220)).tick();

    final cycle = store.loopCycles.single;
    expect(cycle.iobUnits, greaterThan(5.0));
    expect(cycle.unitsPerHour, lessThanOrEqualTo(1.0));
  });

  group('a rate the user set is an instruction, not a suggestion', () {
    /// Setting a temp basal before a run and having the automation quietly put a
    /// correction back five minutes later is the way an automated system undoes
    /// a decision without ever saying so.
    test('a user rate is left running', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      delivery = PodDeliveryStatus.tempBasalActive;
      await store.saveTemporaryBasal(PodTemporaryBasal(
        unitsPerHour: 0,
        start: clock.subtract(const Duration(minutes: 10)),
        end: clock.add(const Duration(minutes: 50)),
      ));

      await runnerWith().tick();

      expect(session.commandsOfType<PodProgramTempBasalCommand>(), isEmpty);
      expect(store.temporaryBasal!.unitsPerHour, 0);
      expect(store.loopCycles.single.delivered, isFalse);
    });

    /// Intent wins over the automation. It does not win over a glucose falling
    /// through the threshold because of a rate set for a run that has finished.
    test('a suspension still overrides a user rate', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      delivery = PodDeliveryStatus.tempBasalActive;
      await store.saveTemporaryBasal(PodTemporaryBasal(
        unitsPerHour: 3.0,
        start: clock.subtract(const Duration(minutes: 10)),
        end: clock.add(const Duration(minutes: 50)),
      ));

      await runnerWith(glucose: glucoseAt(clock, mgdl: 70)).tick();

      final programmed = session.commandsOfType<PodProgramTempBasalCommand>();
      expect(programmed, hasLength(1));
      expect(programmed.single.rate.unitsPerHour, 0);
      expect(store.loopCycles.single.reason, LoopReason.suspendedLow);
    });

    /// The loop's own rate from the previous cycle must not be mistaken for the
    /// user's, or it would only ever program once and then defer to itself.
    test('the automation replaces its own rate', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      delivery = PodDeliveryStatus.tempBasalActive;
      await store.saveTemporaryBasal(PodTemporaryBasal(
        unitsPerHour: 1.5,
        start: clock.subtract(const Duration(minutes: 5)),
        end: clock.add(const Duration(minutes: 25)),
        automated: true,
      ));

      await runnerWith().tick();

      expect(session.commandsOfType<PodProgramTempBasalCommand>(), hasLength(1));
      expect(store.temporaryBasal!.automated, isTrue);
    });
  });

  group('an unreachable pod switches the automation back to basal', () {
    test('a pod out of reach past the fuse stops the automation', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      connection.reachable = false;
      await store.markSeen(clock.subtract(const Duration(minutes: 45)));

      await runnerWith().tick();

      expect(store.loopMode, PodLoopMode.off);
      expect(store.loopStop, PodLoopStop.podUnreachable);
    });

    /// Stopping without saying so leaves the user believing their delivery is
    /// still being managed.
    test('the user is told it stopped', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      connection.reachable = false;
      await store.markSeen(clock.subtract(const Duration(minutes: 45)));

      await runnerWith().tick();

      expect(announced, [PodLoopStop.podUnreachable]);
    });

    /// Once off, it is off. Repeating the notice every cycle would train the
    /// user to swipe it away.
    test('it is announced once, not every cycle', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      connection.reachable = false;
      await store.markSeen(clock.subtract(const Duration(minutes: 45)));
      final runner = runnerWith();

      await runner.tick();
      clock = clock.add(PodLoopRunner.cycleInterval);
      await runner.tick();

      expect(announced, hasLength(1));
    });

    /// One missed cycle is not a lost pod. Stopping on the first failure would
    /// drop the automation every time the phone was in another room.
    test('a single missed cycle leaves the automation on', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      connection.reachable = false;
      await store.markSeen(clock.subtract(const Duration(minutes: 6)));

      await runnerWith().tick();

      expect(store.loopMode, PodLoopMode.engaged);
    });

    /// A pod in alarm needs replacing, and no later cycle changes that. Left
    /// engaged it would report an unavailable pod every five minutes forever.
    test('a pod in alarm stops the automation', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      var alarming = false;
      session = ScriptedSession(
        statusFor: () => statusBody(
          lifecycle: alarming
              ? PodLifecycleStatus.alarm
              : PodLifecycleStatus.runningAboveMinimumVolume,
        ),
      );
      connection = ScriptedConnection(store: store, session: session);
      alarming = true;

      await runnerWith().tick();

      expect(store.loopMode, PodLoopMode.off);
      expect(store.loopStop, PodLoopStop.podNotDelivering);
      expect(session.commandsOfType<PodProgramTempBasalCommand>(), isEmpty);
    });

    /// A bolus finishes in a minute or two. Ending the automation over one would
    /// mean every meal switched it off.
    test('a running bolus does not stop the automation', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      delivery = PodDeliveryStatus.bolusAndBasalActive;

      await runnerWith().tick();

      expect(store.loopMode, PodLoopMode.engaged);
      expect(store.loopCycles.single.reason, LoopReason.podUnavailable);
    });

    test('a pod that is gone stops the automation', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      await store.forgetPod();
      await store.saveLoopMode(PodLoopMode.engaged);

      await runnerWith().tick();

      expect(store.loopMode, PodLoopMode.off);
      expect(store.loopStop, PodLoopStop.noPod);
    });
  });

  /// The mode is toggled in the UI isolate and the store's cache is per isolate.
  /// Without a re-read the service would keep programming rates for up to a full
  /// store-refresh interval after the user switched the automation off.
  test('the mode is re-read before a cycle acts on it', () async {
    await store.saveLoopMode(PodLoopMode.engaged);
    final runner = runnerWith();
    backing['pod.loop_mode'] = PodLoopMode.off.name;

    await runner.tick();

    expect(connection.opened, 0);
    expect(store.loopCycles, isEmpty);
  });

  /// A rate renewed every five minutes but programmed for thirty could look like
  /// it stacks: twelve cycles an hour, each asking for half an hour of insulin.
  ///
  /// It does not, on either level. The POD holds one temporary rate at a time and
  /// a new program replaces it, which is why each cycle cancels a running one
  /// first. And the LEDGER bills each rate for the stretch it actually ran, not
  /// for the fuse it was programmed with, which is why the booking happens before
  /// the rate is replaced.
  ///
  /// The invariant checked here is the one that matters: what the ledger books
  /// equals the integral of the rates that actually ran.
  group('renewing a rate replaces it, it does not stack', () {
    setUp(() async {
      await store.saveLoopMode(PodLoopMode.engaged);
      delivery = PodDeliveryStatus.tempBasalActive;
      // Start the accounting mark exactly at the first cycle, so the sum is the
      // hour under test and not the hour plus whatever window was already open.
      await store.addBasalDelivery(at: clock, units: 0, countedTo: clock);
    });

    /// Thirteen cycles five minutes apart, so a full hour of windows is closed.
    Future<void> runAnHour() async {
      final runner = runnerWith();
      for (var cycle = 0; cycle < 13; cycle++) {
        await runner.tick();
        clock = clock.add(PodLoopRunner.cycleInterval);
      }
    }

    /// Every cycle's rate multiplied by the five minutes it ran before the next
    /// one replaced it.
    double integralOfProgrammedRates() {
      final cycles = store.loopCycles.where((entry) => entry.delivered).toList();
      final minutes = PodLoopRunner.cycleInterval.inMinutes;
      return cycles.fold<double>(
        0,
        (sum, entry) => sum + entry.unitsPerHour * minutes / 60,
      );
    }

    double bookedUnits() => store.pendingBasalDeliveries
        .fold<double>(0, (sum, entry) => sum + (entry['units'] as num).toDouble());

    test('the ledger books the integral of the rates that ran', () async {
      await runAnHour();

      // One cycle's window is still open at the end, so the ledger is behind the
      // integral by exactly that last stretch and never ahead of it.
      final integral = integralOfProgrammedRates();
      final lastStretch = store.loopCycles.first.unitsPerHour *
          PodLoopRunner.cycleInterval.inMinutes /
          60;

      expect(bookedUnits(), closeTo(integral - lastStretch, 0.02));
    });

    /// The shape the fear takes: if each cycle were billed for the half hour it
    /// programmed, an hour would book six times the insulin that ran.
    test('it is nowhere near the fuse-length reading of the same cycles',
        () async {
      await runAnHour();

      final asIfEachRanItsFuse = store.loopCycles
          .where((entry) => entry.delivered)
          .fold<double>(
            0,
            (sum, entry) =>
                sum + entry.unitsPerHour * LoopLimits.fuse.inMinutes / 60,
          );

      expect(bookedUnits(), lessThan(asIfEachRanItsFuse / 4));
    });

    test('an hour of cycles books about an hour of insulin', () async {
      await runAnHour();

      // An hour of delivery cannot exceed an hour at the rate ceiling, however
      // many times the rate was renewed inside it.
      expect(bookedUnits(), greaterThan(0.5));
      expect(bookedUnits(),
          lessThanOrEqualTo(LoopLimits.defaultMaxUnitsPerHour + 1e-6));
    });

    test('only one temporary rate is ever stored', () async {
      await runAnHour();

      final running = store.temporaryBasal!;
      expect(running.automated, isTrue);
      expect(running.end.difference(running.start), LoopLimits.fuse);
    });

    /// Each cycle cancels before it programs, so the pod is never asked to hold
    /// two temporary rates at once.
    test('every programmed rate is preceded by a cancel', () async {
      await runAnHour();

      final programs =
          session.commandsOfType<PodProgramTempBasalCommand>().length;
      final cancels = session.commandsOfType<PodStopDeliveryCommand>().length;

      expect(programs, greaterThan(1));
      expect(cancels, programs);
    });
  });

  group('cycles are paced', () {
    test('a second cycle inside the interval does not run', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      final runner = runnerWith();

      await runner.tick();
      await runner.tick();

      expect(connection.opened, 1);
    });

    test('a cycle runs again once the interval has passed', () async {
      await store.saveLoopMode(PodLoopMode.engaged);
      final runner = runnerWith();

      await runner.tick();
      clock = clock.add(PodLoopRunner.cycleInterval);
      await runner.tick();

      expect(connection.opened, 2);
    });
  });
}
