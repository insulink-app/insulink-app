import 'dart:convert';
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
    // Byte 6 is the prime, byte 7 the cannula. See PodSetUniqueIdResponse.
    body[6] = primePulses;
    body[7] = cannulaPulses;
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
  /// What an interrupted attempt had already recorded, as a resume works from.
  const recordedFacts = PodActivationFacts(
    uniqueId: 4241,
    lotNumber: 135,
    podSequenceNumber: 7,
    primePulses: 52,
    cannulaInsertionPulses: 10,
    primePumpRateEighthSeconds: 8,
    expirationHours: 80,
  );
  final basal = PodBasalProgram([
    const PodBasalSegment(startSlot: 0, endSlot: 48, rateHundredthUnitsPerHour: 80),
  ]);

  ({
    PodActivation activation,
    List<PodActivationStep> steps,
    List<int> confirmations,
    List<String> reconnects,
    List<PodActivationFacts> recordedFacts,
  }) build(
    ScriptedPod pod, {
    bool confirmCannula = true,
    PodActivationFacts? knownFacts,
  }) {
    final steps = <PodActivationStep>[];
    final confirmations = <int>[];
    final reconnects = <String>[];
    final recordedFacts = <PodActivationFacts>[];
    return (
      activation: PodActivation(
        sendCommand: pod.send,
        podUniqueId: 4241,
        onStep: (step) async => steps.add(step),
        confirmCannulaInsertion: () async {
          confirmations.add(1);
          return confirmCannula;
        },
        reopenLink: () async => reconnects.add('reopened'),
        onFacts: (facts) async => recordedFacts.add(facts),
        knownFacts: knownFacts,
        now: () => DateTime(2026, 3, 1, 9, 30),
        wait: (_) async {},
      ),
      steps: steps,
      confirmations: confirmations,
      reconnects: reconnects,
      recordedFacts: recordedFacts,
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
    final harness = build(pod, knownFacts: recordedFacts);
    await harness.activation.primePod(from: PodActivationStep.activationAlertSet);

    expect(harness.steps, [
      PodActivationStep.priming,
      PodActivationStep.primed,
    ]);
    // No second alert programming, and the prime is not re-sent twice.
    expect(
      pod.commands.where((command) => command.type == PodCommandType.programAlerts),
      isEmpty,
    );
  });

  group('the one-shot identity commands are never re-sent', () {
    /// The version read is addressed to the discovery id, which the pod stops
    /// answering on the moment it has an id of its own, and assigning that id is
    /// one-shot. Re-sending either on a resume would hang the activation on a pod
    /// that will never answer.
    test('a resume past the identity asks the pod nothing about itself', () async {
      final pod = ScriptedPod();
      final harness = build(pod, knownFacts: recordedFacts);
      await harness.activation.primePod(from: PodActivationStep.identitySet);

      expect(
        pod.commands.map((command) => command.type),
        isNot(contains(PodCommandType.getVersion)),
      );
      expect(
        pod.commands.map((command) => command.type),
        isNot(contains(PodCommandType.setUniqueId)),
      );
    });

    /// The prime volume then has to come from the record, since the pod can no
    /// longer be asked for it.
    test('the recorded volumes are what a resumed prime delivers', () async {
      final pod = ScriptedPod();
      final harness = build(
        pod,
        knownFacts: const PodActivationFacts(
          uniqueId: 4241,
          lotNumber: 135,
          podSequenceNumber: 7,
          primePulses: 44,
          cannulaInsertionPulses: 10,
          primePumpRateEighthSeconds: 8,
          expirationHours: 80,
        ),
      );
      await harness.activation.primePod(from: PodActivationStep.identitySet);

      expect(
        pod.commands.whereType<PodProgramBolusCommand>().single.amount.pulses,
        44,
      );
    });

    /// Better a clear stop than commands sent to a pod that cannot answer them.
    test('a resume with nothing recorded refuses to guess', () async {
      final pod = ScriptedPod();
      final harness = build(pod);

      await expectLater(
        () => harness.activation.primePod(from: PodActivationStep.identitySet),
        throwsA(isA<PodActivationException>()),
      );
      expect(pod.commands, isEmpty);
    });

    /// Before the id is assigned the pod can still be asked, so an interruption
    /// there simply asks again.
    test('an interruption before the identity asks again', () async {
      final pod = ScriptedPod();
      final harness = build(pod);
      await harness.activation.primePod(from: PodActivationStep.gotVersion);

      expect(
        pod.commands.map((command) => command.type).take(2),
        [PodCommandType.getVersion, PodCommandType.setUniqueId],
      );
    });

    test('what the pod reported is recorded before anything is done with it', () async {
      final pod = ScriptedPod(primePulses: 52);
      final harness = build(pod);
      await harness.activation.primePod(from: PodActivationStep.notStarted);

      expect(harness.recordedFacts.single.primePulses, 52);
      expect(harness.recordedFacts.single.expirationHours, 80);
    });

    test('the record survives a round trip through JSON', () {
      final restored = PodActivationFacts.fromJson(
        jsonDecode(jsonEncode(recordedFacts.toJson())) as Map<String, dynamic>,
      );
      expect(restored.primePulses, recordedFacts.primePulses);
      expect(restored.cannulaInsertionPulses, recordedFacts.cannulaInsertionPulses);
      expect(restored.primePumpRateEighthSeconds,
          recordedFacts.primePumpRateEighthSeconds);
      expect(restored.uniqueId, recordedFacts.uniqueId);
      expect(restored.lotNumber, recordedFacts.lotNumber);
      expect(restored.podSequenceNumber, recordedFacts.podSequenceNumber);
      expect(restored.expirationHours, recordedFacts.expirationHours);
    });
  });

  test('a resume past priming does not deliver insulin again', () async {
    final pod = ScriptedPod();
    final harness = build(pod, knownFacts: recordedFacts);
    await harness.activation.primePod(from: PodActivationStep.primed);

    expect(pod.commands.whereType<PodProgramBolusCommand>(), isEmpty);
    expect(harness.steps, isEmpty);
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

  group('the cannula insertion is gated by a confirmation', () {
    test('nothing is driven into the body until it is confirmed', () async {
      final pod = ScriptedPod(cannulaPulses: 10);
      final harness = build(pod, confirmCannula: false);
      final facts = await harness.activation
          .primePod(from: PodActivationStep.notStarted);
      harness.steps.clear();
      pod.commands.clear();

      await expectLater(
        harness.activation.startDelivery(
          from: PodActivationStep.primed,
          facts: facts,
          basalProgram: basal,
        ),
        throwsA(isA<PodActivationCancelled>()),
      );

      expect(harness.confirmations, hasLength(1));
      // The basal and alerts ran; the cannula bolus did not.
      expect(pod.commands.whereType<PodProgramBolusCommand>(), isEmpty);
      expect(harness.steps, [
        PodActivationStep.basalSet,
        PodActivationStep.lifecycleAlertsSet,
      ]);
    });

    test('a decline leaves the activation exactly where it was', () async {
      final pod = ScriptedPod();
      final harness = build(pod, confirmCannula: false);
      final facts = await harness.activation
          .primePod(from: PodActivationStep.notStarted);
      harness.steps.clear();

      await expectLater(
        harness.activation.startDelivery(
          from: PodActivationStep.lifecycleAlertsSet,
          facts: facts,
          basalProgram: basal,
        ),
        throwsA(isA<PodActivationCancelled>()),
      );

      expect(harness.steps, isEmpty);
    });

    test('a confirmation lets exactly the pod-requested dose through', () async {
      final pod = ScriptedPod(cannulaPulses: 10);
      final harness = build(pod);
      final facts = await harness.activation
          .primePod(from: PodActivationStep.notStarted);
      pod.commands.clear();

      await harness.activation.startDelivery(
        from: PodActivationStep.primed,
        facts: facts,
        basalProgram: basal,
      );

      expect(harness.confirmations, hasLength(1));
      final cannula = pod.commands.whereType<PodProgramBolusCommand>().single;
      expect(cannula.amount.pulses, 10);
    });

    test('the confirmation is asked once, not once per command', () async {
      final pod = ScriptedPod();
      final harness = build(pod);
      final facts = await harness.activation
          .primePod(from: PodActivationStep.notStarted);
      await harness.activation.startDelivery(
        from: PodActivationStep.primed,
        facts: facts,
        basalProgram: basal,
      );
      expect(harness.confirmations, hasLength(1));
    });

    /// A resume past the insertion must not ask again: the needle is already in,
    /// and prompting would imply it is about to happen a second time.
    test('a resume past the insertion does not ask', () async {
      final pod = ScriptedPod();
      final harness = build(pod, confirmCannula: false);
      final facts = await harness.activation
          .primePod(from: PodActivationStep.notStarted);
      pod.commands.clear();

      await harness.activation.startDelivery(
        from: PodActivationStep.insertingCannula,
        facts: facts,
        basalProgram: basal,
      );

      expect(harness.confirmations, isEmpty);
      expect(pod.commands.whereType<PodProgramBolusCommand>(), isEmpty);
    });

    test('priming is not gated — the pod is still off the body', () async {
      final pod = ScriptedPod();
      final harness = build(pod, confirmCannula: false);
      await harness.activation.primePod(from: PodActivationStep.notStarted);
      expect(harness.confirmations, isEmpty);
      expect(pod.commands.whereType<PodProgramBolusCommand>(), hasLength(1));
    });
  });

  group('the link is re-opened after each stretch of waiting', () {
    /// The pod hangs up on an idle link, and priming takes close to a minute. The
    /// verification that follows would otherwise be sent down a dead link, which
    /// would fail every activation at exactly that step.
    test('priming reconnects before it verifies', () async {
      final pod = ScriptedPod();
      final harness = build(pod);
      await harness.activation.primePod(from: PodActivationStep.notStarted);
      expect(harness.reconnects, hasLength(1));
    });

    test('the cannula insertion reconnects before it verifies', () async {
      final pod = ScriptedPod();
      final harness = build(pod);
      final facts = await harness.activation
          .primePod(from: PodActivationStep.notStarted);
      harness.reconnects.clear();

      await harness.activation.startDelivery(
        from: PodActivationStep.primed,
        facts: facts,
        basalProgram: basal,
      );
      expect(harness.reconnects, hasLength(1));
    });

    /// A reconnect must never precede a command that delivers — retrying one that
    /// may already have run is how a dose is given twice.
    test('a resume that delivers nothing reconnects nothing', () async {
      final pod = ScriptedPod();
      final harness = build(pod, knownFacts: recordedFacts);
      await harness.activation.primePod(from: PodActivationStep.primed);
      expect(harness.reconnects, isEmpty);
      expect(pod.commands.whereType<PodProgramBolusCommand>(), isEmpty);
    });

    test('a declined cannula confirmation reconnects nothing', () async {
      final pod = ScriptedPod();
      final harness = build(pod, confirmCannula: false);
      final facts = await harness.activation
          .primePod(from: PodActivationStep.notStarted);
      harness.reconnects.clear();

      await expectLater(
        harness.activation.startDelivery(
          from: PodActivationStep.primed,
          facts: facts,
          basalProgram: basal,
        ),
        throwsA(isA<PodActivationCancelled>()),
      );
      expect(harness.reconnects, isEmpty);
    });
  });

  group('the pod command counter is carried on, not forgotten', () {
    /// The pod treats a repeated sequence number as the command it already ran. If
    /// the activation dropped its counter, the next command would start again at
    /// one — and a bolus would be quietly ignored while the app recorded it.
    test('it advances across the whole activation', () async {
      final pod = ScriptedPod();
      final harness = build(pod);
      final facts = await harness.activation
          .primePod(from: PodActivationStep.notStarted);
      final afterPriming = harness.activation.commandSequence;
      expect(afterPriming, greaterThan(0));

      await harness.activation.startDelivery(
        from: PodActivationStep.primed,
        facts: facts,
        basalProgram: basal,
      );
      expect(harness.activation.commandSequence, isNot(afterPriming));
    });

    test('a resumed activation continues from where the last one stopped', () async {
      final pod = ScriptedPod();
      final steps = <PodActivationStep>[];
      final resumed = PodActivation(
        sendCommand: pod.send,
        podUniqueId: 4241,
        onStep: (step) async => steps.add(step),
        confirmCannulaInsertion: () async => true,
        reopenLink: () async {},
        onFacts: (_) async {},
        knownFacts: recordedFacts,
        startFromSequence: 9,
        now: () => DateTime(2026, 3, 1, 9, 30),
        wait: (_) async {},
      );
      await resumed.primePod(from: PodActivationStep.identitySet);
      expect(pod.commands.first.sequenceNumber, 10,
          reason: 'it must not restart at one');
    });

    test('the counter stays inside the four bits the wire gives it', () async {
      final pod = ScriptedPod();
      final wrapping = PodActivation(
        sendCommand: pod.send,
        podUniqueId: 4241,
        onStep: (_) async {},
        confirmCannulaInsertion: () async => true,
        reopenLink: () async {},
        onFacts: (_) async {},
        knownFacts: recordedFacts,
        startFromSequence: 15,
        now: () => DateTime(2026, 3, 1, 9, 30),
        wait: (_) async {},
      );
      await wrapping.primePod(from: PodActivationStep.identitySet);
      expect(pod.commands.first.sequenceNumber, 0, reason: '15 wraps to 0');
      for (final command in pod.commands) {
        expect(command.sequenceNumber, inInclusiveRange(0, 15));
      }
    });
  });
}
