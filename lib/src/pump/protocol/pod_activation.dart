import 'package:insulink/src/pump/protocol/pod_activation_commands.dart';
import 'package:insulink/src/pump/protocol/pod_activation_state.dart';
import 'package:insulink/src/pump/protocol/pod_alerts_command.dart';
import 'package:insulink/src/pump/protocol/pod_basal_command.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_control_commands.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_ids.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

/// Drives a pod from filled to running.
///
/// Split into two phases on purpose, because the pod is in a different place
/// physically for each: phase one primes a pod that is still off the body, phase
/// two programs basal and seats the cannula once the user has attached it. The UI
/// must not run them back to back without the user confirming the pod is on.
///
/// Every step records itself in [onStep] BEFORE the next one runs, so an
/// interruption resumes at the right place. Two steps deliver insulin — the prime
/// and the cannula insertion — and both use volumes the pod itself reported, not
/// constants of ours.
class PodActivation {
  PodActivation({
    required this.sendCommand,
    required this.podUniqueId,
    required this.onStep,
    this.nonce = fixedNonce,
    this.now = DateTime.now,
    this.wait = _realWait,
  });

  /// The DASH pod does not use the rolling nonce its predecessor did; a fixed
  /// value is what the reference implementations send.
  static const int fixedNonce = 0;

  /// Sends one command and returns the pod's reply.
  ///
  /// Narrower than the whole session on purpose: activation only ever does
  /// command-and-reply, and taking just that makes the sequence testable against
  /// a scripted pod without a live link.
  final Future<PodResponse> Function(PodCommand command) sendCommand;

  /// The id this activation assigns to the pod.
  ///
  /// NOT the controller's own id. The pod takes the controller address with its
  /// low two bits replaced (see [PodId.peripheral]), so a controller on 4242
  /// gives the pod 4241. Passing the controller's own id instead would make the
  /// source and destination of every later message identical.
  final int podUniqueId;

  /// Records progress durably. Awaited before the next step runs.
  final Future<void> Function(PodActivationStep step) onStep;

  final int nonce;
  final DateTime Function() now;
  final Future<void> Function(Duration duration) wait;

  static Future<void> _realWait(Duration duration) => Future<void>.delayed(duration);

  late final PodActivationCommands _commands = PodActivationCommands(
    sendCommand: sendCommand,
    wait: wait,
    nonce: nonce,
  );

  int get _nextSequence => _commands.nextSequence;

  /// Phase one: identify the pod, bind it to this controller, and prime it.
  ///
  /// Runs with the pod still off the body. Returns what the pod reported, which
  /// phase two needs.
  Future<PodActivationFacts> primePod({
    required PodActivationStep from,
  }) async {
    final version = await _readVersion(from);
    final identity = await _setIdentity(from, version);
    final facts = PodActivationFacts(
      uniqueId: identity.uniqueId,
      lotNumber: version.lotNumber,
      podSequenceNumber: version.podSequenceNumber,
      primePulses: identity.primePulses,
      cannulaInsertionPulses: identity.cannulaInsertionPulses,
      primePumpRateEighthSeconds: identity.primePumpRateEighthSeconds,
      expirationHours: identity.expirationHours,
    );

    if (from.isBefore(PodActivationStep.activationAlertSet)) {
      await _commands.expectStatus(PodProgramAlertsCommand(
        uniqueId: facts.uniqueId,
        sequenceNumber: _nextSequence,
        nonce: nonce,
        configurations: PodProgramAlertsCommand.unfinishedActivation(),
      ));
      await onStep(PodActivationStep.activationAlertSet);
    }

    if (from.isBefore(PodActivationStep.priming)) {
      await _commands.deliverPulses(facts, facts.primePulses, facts.uniqueId);
      await onStep(PodActivationStep.priming);
      await wait(facts.deliveryTimeFor(facts.primePulses));
    }

    if (from.isBefore(PodActivationStep.primed)) {
      await _commands.awaitDeliveryIdle(facts.uniqueId, 'priming');
      await onStep(PodActivationStep.primed);
    }
    return facts;
  }

  /// Phase two: program the basal schedule, set the pod's own alerts, and seat
  /// the cannula. Runs only once the user has confirmed the pod is on the body.
  Future<void> startDelivery({
    required PodActivationStep from,
    required PodActivationFacts facts,
    required PodBasalProgram basalProgram,
  }) async {
    if (from.isBefore(PodActivationStep.basalSet)) {
      await _commands.expectStatus(PodProgramBasalCommand(
        uniqueId: facts.uniqueId,
        sequenceNumber: _nextSequence,
        nonce: nonce,
        program: basalProgram,
        now: now(),
      ));
      await onStep(PodActivationStep.basalSet);
    }

    if (from.isBefore(PodActivationStep.lifecycleAlertsSet)) {
      await _commands.expectStatus(PodProgramAlertsCommand(
        uniqueId: facts.uniqueId,
        sequenceNumber: _nextSequence,
        nonce: nonce,
        configurations: PodProgramAlertsCommand.lifecycleDefaults(
          expiryMinutes: facts.expirationHours * 60,
        ),
      ));
      await onStep(PodActivationStep.lifecycleAlertsSet);
    }

    if (from.isBefore(PodActivationStep.insertingCannula)) {
      await _commands.deliverPulses(facts, facts.cannulaInsertionPulses, facts.uniqueId);
      await onStep(PodActivationStep.insertingCannula);
      await wait(facts.deliveryTimeFor(facts.cannulaInsertionPulses));
    }

    if (from.isBefore(PodActivationStep.running)) {
      final status = await _commands.awaitDeliveryIdle(facts.uniqueId, 'cannula insertion');
      if (!status.lifecycle.isRunning) {
        throw PodActivationException(
          'Pod finished activation in state ${status.lifecycle.name}',
        );
      }
      await onStep(PodActivationStep.running);
    }
  }

  Future<PodVersionResponse> _readVersion(PodActivationStep from) async {
    final response = await sendCommand(
      PodGetVersionCommand(sequenceNumber: _nextSequence),
    );
    if (response is! PodVersionResponse) {
      throw PodActivationException('Pod did not report its version: $response');
    }
    if (response.lifecycle == PodLifecycleStatus.alarm) {
      throw PodActivationException('Pod is already in alarm and cannot be used');
    }
    await onStep(PodActivationStep.gotVersion);
    return response;
  }

  Future<PodSetUniqueIdResponse> _setIdentity(
    PodActivationStep from,
    PodVersionResponse version,
  ) async {
    final response = await sendCommand(PodSetUniqueIdCommand(
      uniqueId: podUniqueId,
      sequenceNumber: _nextSequence,
      lotNumber: version.lotNumber,
      podSequenceNumber: version.podSequenceNumber,
      activatedAt: now(),
    ));
    if (response is! PodSetUniqueIdResponse) {
      throw PodActivationException('Pod did not accept its identity: $response');
    }
    if (response.primePulses <= 0 || response.cannulaInsertionPulses <= 0) {
      throw PodActivationException(
        'Pod reported an implausible prime volume; refusing to deliver',
      );
    }
    await onStep(PodActivationStep.identitySet);
    return response;
  }
}
