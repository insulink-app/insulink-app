import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_connection.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_retry.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';
import 'package:insulink/src/pump/protocol/pod_message_io.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/protocol/pod_session_keys.dart';
import 'package:insulink/src/pump/protocol/pod_ids.dart';
import 'package:insulink/src/pump/protocol/session_cipher.dart';

import '../support/secure_storage_mock.dart';
import 'fake_pod.dart';
import 'fake_secure_storage.dart';
import 'loop_input.dart';

/// A pod that is running and delivering basal, with plenty in the reservoir.
Uint8List runningBody() {
  final body = Uint8List(10);
  body[0] = 0x1d;
  body[1] = (PodDeliveryStatus.basalActive.value << 4) |
      PodLifecycleStatus.runningAboveMinimumVolume.value;
  ByteData.view(body.buffer)
    ..setUint32(2, 0)
    ..setUint32(6, 0x3FF);
  return body;
}

class ScriptedSession extends PodSession {
  ScriptedSession({required this.onBolus})
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

  /// What the pod does with a bolus. Throwing simulates a lost confirmation.
  final PodResponse Function() onBolus;

  int bolusesSent = 0;

  @override
  Future<PodResponse> run(PodCommand command) async {
    if (command is PodProgramBolusCommand) {
      bolusesSent++;
      return onBolus();
    }
    return PodStatusResponse(runningBody());
  }
}

class FlakyConnection extends PodConnection {
  FlakyConnection({required super.store, required this.session});

  final ScriptedSession session;

  /// Attempts that fail before the pod answers. The failure happens during the
  /// connect, so no command has been sent.
  int failFirst = 0;

  int opened = 0;

  @override
  Future<PodSession> openSession({bool allowScan = true}) async {
    opened++;
    if (opened <= failFirst) {
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
  late FlakyConnection connection;

  const immediate = PodRetry(attempts: 3, firstDelay: Duration.zero);

  Future<PodController> controllerWith(
    PodResponse Function() onBolus, {
    int failFirst = 0,
  }) async {
    installSecureStorageMock();
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
    await store.savePairing(
      uniqueId: 0x1091,
      longTermKey: FakeSecureStorage.dummyKey,
      lotNumber: 1,
      podSequenceNumber: 1,
      activatedAt: DateTime.now().subtract(const Duration(hours: 4)),
      resetSessionCounters: true,
    );
    await store.saveActivationStep('running');
    session = ScriptedSession(onBolus: onBolus);
    connection = FlakyConnection(store: store, session: session)
      ..failFirst = failFirst;
    return PodController(
      store: store,
      retry: immediate,
      connection: connection,
    );
  }

  PodResponse delivering() => PodStatusResponse(hex('1D580519C00E0039A7FF8085'));

  group('a link that fails before anything is sent', () {
    /// The user's report: the bolus does not go through because the link fails.
    /// Nothing was asked of the pod, so trying again is free.
    test('is tried again and the bolus still goes out', () async {
      final controller = await controllerWith(delivering, failFirst: 2);

      final response = await controller.sendBolus(
        PodBolusAmount.fromUnits(2.0),
        refuseIf: (_) => null,
      );

      expect(connection.opened, 3);
      expect(session.bolusesSent, 1, reason: 'one dose, however many connects');
      expect(response, isA<PodStatusResponse>());
    });

    test('gives up after the last attempt and reports the real failure',
        () async {
      final controller = await controllerWith(delivering, failFirst: 99);

      await expectLater(
        controller.sendBolus(
          PodBolusAmount.fromUnits(2.0),
          refuseIf: (_) => null,
        ),
        throwsA(isA<PodLinkException>()),
      );

      expect(connection.opened, 3);
      expect(session.bolusesSent, 0);
    });
  });

  group('a bolus that may already be in the body', () {
    /// The boundary the whole retry policy exists to hold. A bolus command that
    /// went out and was never answered may have been delivered, and a small dose
    /// can finish before a second attempt reads the pod, so the guard that
    /// refuses while bolusing cannot be relied on to catch it either.
    test('is never sent a second time', () async {
      final controller = await controllerWith(
        () => throw PodCommandOutcomeUnknown('Pod sent no reply'),
      );

      await expectLater(
        controller.sendBolus(
          PodBolusAmount.fromUnits(2.0),
          refuseIf: (_) => null,
        ),
        throwsA(isA<PodCommandOutcomeUnknown>()),
      );

      expect(session.bolusesSent, 1);
    });
  });

  group('a dose a guard refused', () {
    /// Repeating the request cannot change the pod's state, so it is reported at
    /// once rather than after three rounds of waiting.
    test('is reported without retrying', () async {
      final controller = await controllerWith(delivering);

      await expectLater(
        controller.sendBolus(
          PodBolusAmount.fromUnits(2.0),
          refuseIf: (_) => 'a bolus is already running',
        ),
        throwsA(isA<PodBolusRefused>()),
      );

      expect(connection.opened, 1);
      expect(session.bolusesSent, 0);
    });
  });
}
