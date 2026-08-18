import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_activation.dart';
import 'package:insulink/src/pump/protocol/pod_activation_state.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

Uint8List hex(String text) => Uint8List.fromList([
      for (var index = 0; index < text.length; index += 2)
        int.parse(text.substring(index, index + 2), radix: 16),
    ]);

/// A pod that answers activation commands the way a filled pod does.
class ScriptedPod {
  ScriptedPod({this.primePulses = 52, this.cannulaPulses = 10});

  final int primePulses;
  final int cannulaPulses;

  final List<PodCommand> commands = <PodCommand>[];

  /// Pulses still to deliver, so a status poll reports progress once.
  int pendingPulses = 0;
  bool alarmOnNextStatus = false;
  bool refuseBasal = false;

  Future<PodResponse> send(PodCommand command) async {
    commands.add(command);
    switch (command.type) {
      case PodCommandType.getVersion:
        return PodVersionResponse(_versionBody);
      case PodCommandType.setUniqueId:
        return PodSetUniqueIdResponse(_identityBody);
      case PodCommandType.programBolus:
        pendingPulses = (command as PodProgramBolusCommand).amount.pulses;
        return PodStatusResponse(_statusBody(
          lifecycle: PodLifecycleStatus.priming,
          bolusPulsesRemaining: pendingPulses,
        ));
      case PodCommandType.programBasal:
        if (refuseBasal) {
          return PodNakResponse(hex('0603070008'));
        }
        return PodStatusResponse(_statusBody());
      case PodCommandType.getStatus:
        if (alarmOnNextStatus) {
          return PodStatusResponse(
              _statusBody(lifecycle: PodLifecycleStatus.alarm));
        }
        if (pendingPulses > 0) {
          final remaining = pendingPulses;
          pendingPulses = 0;
          return PodStatusResponse(_statusBody(
            lifecycle: PodLifecycleStatus.priming,
            bolusPulsesRemaining: remaining,
          ));
        }
        return PodStatusResponse(_statusBody());
      default:
        return PodStatusResponse(_statusBody());
    }
  }

  Uint8List get _versionBody {
    final body = Uint8List(23);
    body[0] = 0x01;
    body[1] = 0x15;
    body[9] = PodLifecycleStatus.filled.value;
    ByteData.view(body.buffer)
      ..setUint32(10, 135556289)
      ..setUint32(14, 681767);
    return body;
  }

  Uint8List get _identityBody {
    final body = Uint8List(29);
    body[0] = 0x01;
    body[1] = 0x1b;
    body[4] = 16; // pump rate, eighth seconds per pulse
    body[5] = 8; // prime pump rate: one pulse per second
    body[6] = cannulaPulses;
    body[7] = primePulses;
    body[8] = 80; // expiration hours
    body[16] = PodLifecycleStatus.uniqueIdSet.value;
    ByteData.view(body.buffer)
      ..setUint32(17, 135556289)
      ..setUint32(21, 681767)
      ..setUint32(25, 4242);
    return body;
  }

  Uint8List _statusBody({
    PodLifecycleStatus lifecycle = PodLifecycleStatus.runningAboveMinimumVolume,
    int bolusPulsesRemaining = 0,
  }) {
    final body = Uint8List(10);
    body[0] = 0x1d;
    body[1] = (PodDeliveryStatus.basalActive.value << 4) | lifecycle.value;
    ByteData.view(body.buffer)
      ..setUint32(2, bolusPulsesRemaining & 0x7FF)
      ..setUint32(6, 0x3FF);
    return body;
  }
}

void main() {
  final basal = PodBasalProgram([
    const PodBasalSegment(startSlot: 0, endSlot: 48, rateHundredthUnitsPerHour: 80),
  ]);

  ({PodActivation activation, List<PodActivationStep> steps}) build(
    ScriptedPod pod,
  ) {
    final steps = <PodActivationStep>[];
    return (
      activation: PodActivation(
        sendCommand: pod.send,
        podUniqueId: 4241,
        onStep: (step) async => steps.add(step),
        now: () => DateTime(2026, 3, 1, 9, 30),
        wait: (_) async {},
      ),
      steps: steps,
    );
  }

  test('phase one identifies, binds and primes the pod in order', () async {
    final pod = ScriptedPod();
    final harness = build(pod);
    final facts = await harness.activation
        .primePod(from: PodActivationStep.notStarted);

    expect(harness.steps, [
      PodActivationStep.gotVersion,
      PodActivationStep.identitySet,
      PodActivationStep.activationAlertSet,
      PodActivationStep.priming,
      PodActivationStep.primed,
    ]);
    expect(pod.commands.map((command) => command.type).take(4), [
      PodCommandType.getVersion,
      PodCommandType.setUniqueId,
      PodCommandType.programAlerts,
      PodCommandType.programBolus,
    ]);
    expect(facts.lotNumber, 135556289);
    expect(facts.podSequenceNumber, 681767);
    expect(facts.expirationHours, 80);
  });

  test('the prime volume is exactly what the pod asked for', () async {
    final pod = ScriptedPod(primePulses: 52);
    final harness = build(pod);
    await harness.activation.primePod(from: PodActivationStep.notStarted);

    final prime = pod.commands
        .whereType<PodProgramBolusCommand>()
        .single;
    expect(prime.amount.pulses, 52);
    expect(prime.amount.units, closeTo(2.6, 1e-9));
    expect(prime.eighthSecondsBetweenPulses, 8);
  });

  test('phase two programs basal, alerts and the cannula bolus', () async {
    final pod = ScriptedPod(cannulaPulses: 10);
    final harness = build(pod);
    final facts = await harness.activation
        .primePod(from: PodActivationStep.notStarted);
    harness.steps.clear();
    pod.commands.clear();

    await harness.activation.startDelivery(
      from: PodActivationStep.primed,
      facts: facts,
      basalProgram: basal,
    );

    expect(harness.steps, [
      PodActivationStep.basalSet,
      PodActivationStep.lifecycleAlertsSet,
      PodActivationStep.insertingCannula,
      PodActivationStep.running,
    ]);
    final cannula = pod.commands.whereType<PodProgramBolusCommand>().single;
    expect(cannula.amount.pulses, 10);
    expect(cannula.amount.units, closeTo(0.5, 1e-9));
  });

  test('a resumed activation does not repeat steps that already ran', () async {
    final pod = ScriptedPod();
    final harness = build(pod);
    await harness.activation.primePod(from: PodActivationStep.activationAlertSet);

    expect(harness.steps, [
      PodActivationStep.gotVersion,
      PodActivationStep.identitySet,
      PodActivationStep.priming,
      PodActivationStep.primed,
    ]);
    // No second alert programming, and the prime is not re-sent twice.
    expect(
      pod.commands.where((command) => command.type == PodCommandType.programAlerts),
      isEmpty,
    );
  });

  test('a resume past priming does not deliver insulin again', () async {
    final pod = ScriptedPod();
    final harness = build(pod);
    await harness.activation.primePod(from: PodActivationStep.primed);

    expect(pod.commands.whereType<PodProgramBolusCommand>(), isEmpty);
    expect(harness.steps, [
      PodActivationStep.gotVersion,
      PodActivationStep.identitySet,
    ]);
  });

  test('a refused basal program stops activation instead of continuing', () async {
    final pod = ScriptedPod()..refuseBasal = true;
    final harness = build(pod);
    final facts = await harness.activation
        .primePod(from: PodActivationStep.notStarted);

    expect(
      () => harness.activation.startDelivery(
        from: PodActivationStep.primed,
        facts: facts,
        basalProgram: basal,
      ),
      throwsA(isA<PodActivationException>()),
    );
  });

  test('a pod that alarms during priming aborts activation', () async {
    final pod = ScriptedPod()..alarmOnNextStatus = true;
    final harness = build(pod);
    expect(
      () => harness.activation.primePod(from: PodActivationStep.priming),
      throwsA(isA<PodActivationException>()),
    );
  });

  test('an implausible pod-reported prime volume is refused', () async {
    final pod = ScriptedPod(primePulses: 0);
    final harness = build(pod);
    expect(
      () => harness.activation.primePod(from: PodActivationStep.notStarted),
      throwsA(isA<PodActivationException>()),
    );
  });

  test('command sequence numbers advance and wrap inside four bits', () async {
    final pod = ScriptedPod();
    final harness = build(pod);
    final facts = await harness.activation
        .primePod(from: PodActivationStep.notStarted);
    await harness.activation.startDelivery(
      from: PodActivationStep.primed,
      facts: facts,
      basalProgram: basal,
    );
    for (final command in pod.commands) {
      expect(command.sequenceNumber, inInclusiveRange(0, 15));
    }
    final numbers = pod.commands.map((command) => command.sequenceNumber).toList();
    expect(numbers.first, 1);
    expect(numbers.toSet().length, greaterThan(1));
  });
}
