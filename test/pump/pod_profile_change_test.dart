import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/basal/basal_profile.dart';
import 'package:insulink/src/pump/pod_basal_adapter.dart';
import 'package:insulink/src/pump/pod_basal_delivery.dart';
import 'package:insulink/src/pump/pod_connection.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_basal_command.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_control_commands.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_ids.dart';
import 'package:insulink/src/pump/protocol/pod_message_io.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/protocol/pod_session_keys.dart';
import 'package:insulink/src/pump/protocol/pod_stop_delivery_command.dart';
import 'package:insulink/src/pump/protocol/pod_temp_basal_command.dart';
import 'package:insulink/src/pump/protocol/session_cipher.dart';

import '../support/secure_storage_mock.dart';
import 'bolus_delivery_test.dart' show statusBody;
import 'fake_pod.dart';
import 'fake_secure_storage.dart';

/// Sending an edited basal profile to a pod that is running a TEMPORARY rate.
///
/// The pod holds one basal delivery. A schedule arriving while a temporary rate
/// is still in progress leaves it with two answers to the same question, and a
/// real pod faulted (alarm 0x31, delivery stopped) the first time this app did
/// exactly that: the automation had just set 0.0 U/h for thirty minutes when an
/// edited profile was shared. AndroidAPS opens its own profile change by ending
/// the temporary rate, and this pins that we do too.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The controller's own post-command bookkeeping reaches for the keystore
  // directly, so without this the operation reports a failure it did not have.
  installSecureStorageMock();

  late Map<String, String> backing;
  late PodStore store;
  late RecordingConnection connection;
  late PodController controller;

  final program = PodBasalAdapter(BasalProfile(
    name: 'flat',
    rates: List<double>.filled(24, 0.8),
    peaks: const [],
    dailyTotal: 19.2,
  )).program;

  setUp(() async {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
    await store.savePairing(
      uniqueId: 4242,
      longTermKey: Uint8List(16),
      lotNumber: 1,
      podSequenceNumber: 2,
      activatedAt: DateTime.now(),
    );
    connection = RecordingConnection(store);
    controller = PodController(store: store, connection: connection);
  });

  /// The POD reports a temporary rate. That, not the app's own record, is what
  /// the decision is made on.
  void podRunsTemporaryRate() {
    connection.session.delivery = PodDeliveryStatus.tempBasalActive;
  }

  Future<void> storeRecordsTemporaryRate() async {
    final started = DateTime.now();
    await store.saveTemporaryBasal(PodTemporaryBasal(
      unitsPerHour: 0,
      start: started,
      end: started.add(const Duration(minutes: 30)),
    ));
  }

  Future<void> runTemporaryRate() async {
    podRunsTemporaryRate();
    await storeRecordsTemporaryRate();
  }

  test('a running temporary rate is ended before the schedule is sent',
      () async {
    await runTemporaryRate();

    await controller.applyBasalProfile(program);

    expect(connection.session.sent.map((sent) => sent.runtimeType), [
      PodGetStatusCommand,
      PodStopDeliveryCommand,
      PodProgramBasalCommand,
    ]);
  });

  /// The user asked for a profile change, not for a cancel. A beep here would
  /// report a step they never took.
  test('ending it is silent', () async {
    await runTemporaryRate();

    await controller.applyBasalProfile(program);

    final stop = connection.session.sent
        .whereType<PodStopDeliveryCommand>()
        .single;
    expect(stop.beep, PodBeep.silent);
    expect(stop.target, PodDeliveryTarget.tempBasal);
  });

  test('the ended rate stops counting as running', () async {
    await runTemporaryRate();

    await controller.applyBasalProfile(program);

    expect(controller.activeTemporaryBasal, isNull);
  });

  /// The case the app's own record cannot answer, and the reason the decision is
  /// taken from the pod. The automation runs in the other isolate and can set a
  /// rate this isolate's cache has never seen; asking the store would find
  /// nothing to cancel while the pod is mid-delivery, which is the fault all over
  /// again.
  test('a rate the app does not know about is still ended', () async {
    podRunsTemporaryRate();

    await controller.applyBasalProfile(program);

    expect(controller.activeTemporaryBasal, isNull);
    expect(
      connection.session.sent.whereType<PodStopDeliveryCommand>(),
      hasLength(1),
    );
  });

  /// And the reverse: a stale record claiming a rate the pod is not running must
  /// not add a delivery command of its own.
  test('a rate only the app believes in sends no stop', () async {
    await storeRecordsTemporaryRate();

    await controller.applyBasalProfile(program);

    expect(connection.session.sent.whereType<PodStopDeliveryCommand>(), isEmpty);
  });

  /// The manual temporary rate goes through the same chokepoint, because a
  /// second rate over a running one is the same violation as a schedule over one.
  test('setting a temporary rate ends the one already running', () async {
    podRunsTemporaryRate();

    await controller.setTemporaryBasal(
      PodTempBasalRate(unitsPerHour: 0.5, minutes: 30),
    );

    expect(connection.session.sent.map((sent) => sent.runtimeType), [
      PodGetStatusCommand,
      PodStopDeliveryCommand,
      PodProgramTempBasalCommand,
    ]);
  });

  /// Nothing to end means nothing sent: the extra command would be a delivery
  /// command issued for no reason, and every one of those is a chance to fault a
  /// pod that was doing nothing wrong.
  test('no temporary rate sends the schedule alone', () async {
    await controller.applyBasalProfile(program);

    expect(connection.session.sent.whereType<PodStopDeliveryCommand>(), isEmpty);
    expect(
      connection.session.sent.whereType<PodProgramBasalCommand>(),
      hasLength(1),
    );
  });

  test('the schedule still reaches the store', () async {
    await runTemporaryRate();

    await controller.applyBasalProfile(program);

    expect(controller.failure, isNull);
    expect(store.basalRates, hasLength(24));
    expect(store.basalRates!.first, closeTo(0.8, 1e-9));
  });
  group('letting go of a pod', () {
    /// The symptom: the pod had genuinely shut down, and the app went on holding
    /// it. The old check asked whether the DELIVERY byte read as a plain
    /// `suspended`, which a deactivated pod is not obliged to report; the
    /// question actually being asked is whether it can still deliver at all.
    test('a deactivated pod is forgotten', () async {
      connection.session.lifecycle = PodLifecycleStatus.deactivated;

      await controller.deactivatePod();

      expect(store.hasPod, isFalse);
      expect(controller.failure, isNull);
    });

    /// A pod in alarm has stopped for good and is never coming back either.
    test('an alarming pod is forgotten', () async {
      connection.session.lifecycle = PodLifecycleStatus.alarm;

      await controller.deactivatePod();

      expect(store.hasPod, isFalse);
    });

    /// The rule that must not bend: a pod can never be paired twice, so a key
    /// dropped while it still delivers leaves nothing able to stop it.
    test('a pod that is still running is kept', () async {
      await controller.deactivatePod();

      expect(store.hasPod, isTrue);
      expect(controller.failure, isNotNull);
    });

    /// The way out when the pod answers nothing at all. It cannot check
    /// anything, on purpose: the user is the one who can see the pod.
    test('an unreachable pod can be dropped by hand', () async {
      await controller.forgetUnreachablePod();

      expect(store.hasPod, isFalse);
      expect(controller.failure, isNull);
    });

    /// The case it exists for. What makes a pod unreachable is that the attempt
    /// to reach it does not finish, so a way out that waits for the app to stop
    /// trying is no way out at all. It has to work MID-operation.
    test('it works while an operation is still in flight', () async {
      connection.session.hold = Completer<void>();
      final inFlight = controller.refresh();
      await pumpEventQueue();

      await controller.forgetUnreachablePod();
      expect(store.hasPod, isFalse);

      connection.session.hold!.complete();
      await inFlight;

      expect(store.hasPod, isFalse, reason: 'the pod does not come back');
    });
  });
}

/// A connection whose session records what it was asked to run.
class RecordingConnection extends PodConnection {
  RecordingConnection(PodStore store) : super(store: store);

  final RecordingSession session = RecordingSession();

  @override
  Future<PodSession> openSession({bool allowScan = true}) async => session;

  @override
  Future<void> close() async {}
}

class RecordingSession extends PodSession {
  RecordingSession()
      : super(
          messageIo: PodMessageIo(FakePodLink(onMessage: (_) async => null)),
          addresses: const PodAddressPair(podUniqueId: 4242),
          keys: PodSessionKeys(
            confidentialityKey: Uint8List(16),
            nonce: SessionNonce(prefix: Uint8List(8), sequence: 1),
            messageSequence: 0,
            eapSequence: 1,
          ),
        );

  final List<PodCommand> sent = <PodCommand>[];

  /// What the pod says it is delivering. A stop for the temporary rate turns it
  /// off, the way the real one does.
  PodDeliveryStatus delivery = PodDeliveryStatus.basalActive;

  /// Where the pod says it is in its life. What deactivation is judged on.
  PodLifecycleStatus lifecycle = PodLifecycleStatus.runningAboveMinimumVolume;

  /// Completed by a test to release a command it is holding open, so an
  /// operation can be observed mid-flight.
  Completer<void>? hold;

  @override
  Future<PodResponse> run(PodCommand command) async {
    sent.add(command);
    if (hold != null) {
      await hold!.future;
    }
    if (command is PodStopDeliveryCommand &&
        command.target == PodDeliveryTarget.tempBasal) {
      delivery = PodDeliveryStatus.basalActive;
    }
    return PodStatusResponse(
      statusBody(delivery: delivery, lifecycle: lifecycle),
    );
  }

}
