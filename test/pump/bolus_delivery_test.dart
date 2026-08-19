import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/bolus_delivery.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_delivery_gate.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';

import 'fake_secure_storage.dart';

Uint8List hex(String text) => Uint8List.fromList([
      for (var index = 0; index < text.length; index += 2)
        int.parse(text.substring(index, index + 2), radix: 16),
    ]);

/// A pod status body built to order, so each case can put the pod in the state
/// the decision under test is about.
Uint8List statusBody({
  PodLifecycleStatus lifecycle = PodLifecycleStatus.runningAboveMinimumVolume,
  PodDeliveryStatus delivery = PodDeliveryStatus.basalActive,
  int bolusPulsesRemaining = 0,
  int reservoirPulses = 0x3FF,
}) {
  final body = Uint8List(10);
  body[0] = 0x1d;
  body[1] = (delivery.value << 4) | lifecycle.value;
  ByteData.view(body.buffer)
    ..setUint32(2, bolusPulsesRemaining & 0x7FF)
    ..setUint32(6, reservoirPulses & 0x3FF);
  return body;
}

/// What a pod that took the bolus answers with: the dose is named in the reply,
/// not merely acknowledged.
PodResponse _acceptedBolus(PodBolusAmount amount) => PodStatusResponse(statusBody(
      delivery: PodDeliveryStatus.bolusAndBasalActive,
      bolusPulsesRemaining: amount.pulses,
    ));

/// A controller whose pod answers however the test needs, so the real decision
/// logic in [BolusDelivery] runs against it without a radio.
class ScriptedPodController extends PodController {
  ScriptedPodController({
    required super.store,
    required super.gate,
    required this.reply,
    Uint8List? initialStatus,
  }) : _statusBody = initialStatus ?? statusBody();

  /// What the pod answers a bolus with. Throwing simulates the link failing.
  final PodResponse Function(PodBolusAmount amount) reply;

  final Uint8List _statusBody;

  final List<PodBolusAmount> sent = <PodBolusAmount>[];

  PodStatusResponse? _status;
  DateTime? _readAt;

  @override
  PodStatusResponse? get status => _status;

  @override
  DateTime? get statusReadAt => _readAt;

  @override
  Future<void> refresh() async {
    _status = PodStatusResponse(_statusBody);
    _readAt = DateTime.now();
  }

  @override
  Future<PodResponse> sendBolus(PodBolusAmount amount) async {
    sent.add(amount);
    return reply(amount);
  }
}

void main() {
  late Map<String, String> backing;
  late PodStore store;

  Future<void> pairPod() => store.savePairing(
        uniqueId: 4242,
        longTermKey: hex('00112233445566778899aabbccddeeff'),
        lotNumber: 1,
        podSequenceNumber: 2,
        activatedAt: DateTime.now(),
      );

  BolusDelivery deliveryFor(
    PodController controller,
    PodDeliveryGate gate, {
    double maxBolus = 10,
    double maxPerHour = 15,
  }) {
    return BolusDelivery(
      controller: controller,
      gate: gate,
      maxBolusUnits: maxBolus,
      maxUnitsPerHour: maxPerHour,
    );
  }

  setUp(() {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  group('with no pump involved the behaviour is unchanged', () {
    test('no pod paired logs the full dose', () async {
      final gate = PodDeliveryGate(true);
      final controller = PodController(store: store, gate: gate);
      final outcome = await deliveryFor(controller, gate)
          .deliver(4.0, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.loggedOnly);
      expect(outcome.recordedUnits, 4.0);
      expect(outcome.byPump, isFalse);
    });

    test('a paired pod with the gate shut still only logs', () async {
      await pairPod();
      final gate = PodDeliveryGate(false);
      final controller = ScriptedPodController(
        store: store,
        gate: gate,
        reply: (_) => throw StateError('must not be reached'),
      );
      final delivery = deliveryFor(controller, gate);
      expect(delivery.usesPump, isFalse);
      final outcome = await delivery.deliver(4.0, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.loggedOnly);
      expect(outcome.recordedUnits, 4.0);
      expect(controller.sent, isEmpty);
    });
  });

  group('with a pod and the gate open', () {
    late PodDeliveryGate gate;

    setUp(() async {
      await pairPod();
      gate = PodDeliveryGate(true);
    });

    ScriptedPodController controllerWith({
      PodResponse Function(PodBolusAmount amount)? reply,
      Uint8List? status,
    }) {
      return ScriptedPodController(
        store: store,
        gate: gate,
        reply: reply ?? _acceptedBolus,
        initialStatus: status,
      );
    }

    test('a healthy pod delivers, and the dose is recorded', () async {
      final controller = controllerWith();
      final outcome = await deliveryFor(controller, gate)
          .deliver(4.0, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.delivered);
      expect(outcome.recordedUnits, 4.0);
      expect(outcome.byPump, isTrue);
      expect(controller.sent.single.pulses, 80);
    });

    /// A well-formed status that does not name the bolus is what a pod sends when
    /// it answers a sequence number it has already run — a cached reply, with no
    /// insulin behind it. Recording that as delivered would suppress the next dose.
    test('a status that does not report a bolus is not counted as delivered', () async {
      final controller = controllerWith(
        reply: (_) => PodStatusResponse(statusBody()),
      );
      final outcome = await deliveryFor(controller, gate)
          .deliver(4.0, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.unknown);
      expect(outcome.recordedUnits, 0);
      expect(outcome.needsAttention, isTrue);
    });

    /// The pod may report only the remaining pulses in the instant before its
    /// delivery flag flips, so either signal on its own is enough.
    test('remaining pulses alone confirm the bolus', () async {
      final controller = controllerWith(
        reply: (amount) => PodStatusResponse(
          statusBody(bolusPulsesRemaining: amount.pulses),
        ),
      );
      final outcome = await deliveryFor(controller, gate)
          .deliver(4.0, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.delivered);
      expect(outcome.recordedUnits, 4.0);
    });

    test('a dose off the pulse grid is refused, not rounded', () async {
      final controller = controllerWith();
      final outcome = await deliveryFor(controller, gate)
          .deliver(1.03, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.refused);
      expect(outcome.recordedUnits, 0);
      expect(controller.sent, isEmpty);
    });

    test('a dose above the user maximum never reaches the pod', () async {
      final controller = controllerWith();
      final outcome = await deliveryFor(controller, gate, maxBolus: 5)
          .deliver(6.0, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.refused);
      expect(controller.sent, isEmpty);
    });

    test('the rolling hourly limit counts insulin already given', () async {
      final controller = controllerWith();
      final outcome = await deliveryFor(controller, gate, maxPerHour: 10)
          .deliver(4.0, deliveredLastHour: 8.0);
      expect(outcome.status, BolusDeliveryStatus.refused);
      expect(controller.sent, isEmpty);
    });

    test('a bolus already running blocks a second one', () async {
      final controller = controllerWith(
        status: statusBody(
          delivery: PodDeliveryStatus.bolusAndBasalActive,
          bolusPulsesRemaining: 20,
        ),
      );
      final outcome = await deliveryFor(controller, gate)
          .deliver(2.0, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.refused);
      expect(controller.sent, isEmpty);
    });

    test('an alarming pod is refused', () async {
      final controller =
          controllerWith(status: statusBody(lifecycle: PodLifecycleStatus.alarm));
      final outcome = await deliveryFor(controller, gate)
          .deliver(2.0, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.refused);
      expect(controller.sent, isEmpty);
    });

    test('more insulin than the reservoir holds is refused', () async {
      // 40 pulses left = 2.0 U.
      final controller = controllerWith(status: statusBody(reservoirPulses: 40));
      final outcome = await deliveryFor(controller, gate)
          .deliver(3.0, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.refused);
      expect(controller.sent, isEmpty);
    });

    test('a pod refusal records no insulin', () async {
      final controller = controllerWith(
        reply: (_) => PodNakResponse(hex('0603070008')),
      );
      final outcome = await deliveryFor(controller, gate)
          .deliver(2.0, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.refused);
      expect(outcome.recordedUnits, 0);
      expect(outcome.detail, contains('illegalParameter'));
    });

    /// The case that decides whether the log can be trusted: the command may have
    /// taken effect, so nothing is recorded and the user is told to look.
    test('an unconfirmed bolus records no insulin and asks for attention', () async {
      final controller = controllerWith(
        reply: (_) => throw PodCommandOutcomeUnknown('confirmation lost'),
      );
      final outcome = await deliveryFor(controller, gate)
          .deliver(2.0, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.unknown);
      expect(outcome.recordedUnits, 0);
      expect(outcome.needsAttention, isTrue);
      expect(outcome.byPump, isFalse);
      expect(outcome.detail, contains('confirmation lost'));
    });

    test('a link failure is reported as a refusal, not as delivered', () async {
      final controller = controllerWith(
        reply: (_) => throw const FormatException('link died'),
      );
      final outcome = await deliveryFor(controller, gate)
          .deliver(2.0, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.refused);
      expect(outcome.recordedUnits, 0);
    });

    test('a zero bolus is never sent to the pod', () async {
      final controller = controllerWith();
      final outcome = await deliveryFor(controller, gate)
          .deliver(0, deliveredLastHour: 0);
      expect(outcome.status, BolusDeliveryStatus.loggedOnly);
      expect(controller.sent, isEmpty);
    });
  });
}
