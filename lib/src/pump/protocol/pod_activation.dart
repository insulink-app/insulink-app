import 'package:flutter/foundation.dart';
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
    required this.confirmCannulaInsertion,
    required this.reopenLink,
    required this.onFacts,
    this.knownFacts,
    this.startFromSequence = 0,
    this.nonce = fixedNonce,
    this.now = DateTime.now,
    this.wait = _realWait,
  });

  /// The DASH pod does not use the rolling nonce its predecessor did; a fixed
  /// value is what the reference implementations send. See [podFixedNonce].
  static const int fixedNonce = podFixedNonce;

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

  /// Asked immediately before the cannula is driven into the body, and only
  /// then. Returning false aborts with [PodActivationCancelled] and no needle
  /// moves.
  ///
  /// Required rather than defaulted on purpose: this is the one step of the
  /// activation that puts a needle under the user's skin, and a caller that
  /// forgot to wire a confirmation would otherwise silently do it unprompted.
  ///
  /// Priming is deliberately NOT behind this. It delivers insulin, but into a pod
  /// that is still off the body, and putting a second identical prompt in front of
  /// it would train the user to tap through both.
  final Future<bool> Function() confirmCannulaInsertion;

  /// Re-establishes the link, called after each stretch spent waiting for the pod
  /// to finish delivering.
  ///
  /// The pod closes its link when nothing is being said to it, and priming takes
  /// close to a minute. Without this the verification that follows would be sent
  /// down a link the pod has already dropped, and every activation would fail at
  /// exactly that step.
  ///
  /// Only ever called before an idempotent status read — never before a delivery
  /// command. Reconnecting and retrying a command that may already have been
  /// carried out is how a dose gets given twice.
  final Future<void> Function() reopenLink;

  /// Records what the pod reported about itself, before anything is done with it.
  ///
  /// The two commands that produce these numbers cannot be repeated, so an
  /// activation that did not hand them on could never be resumed past the point
  /// where it assigned the pod its id.
  final Future<void> Function(PodActivationFacts facts) onFacts;

  /// What an earlier attempt recorded, for a resume. Ignored while the pod has
  /// not been given its id yet, since at that point it can still be asked.
  final PodActivationFacts? knownFacts;

  /// Where the pod command counter stands, carried in so a resumed activation does
  /// not reuse a number the earlier attempt already spent.
  final int startFromSequence;

  final int nonce;
  final DateTime Function() now;
  final Future<void> Function(Duration duration) wait;

  static Future<void> _realWait(Duration duration) => Future<void>.delayed(duration);

  late final PodActivationCommands _commands = PodActivationCommands(
    sendCommand: sendCommand,
    wait: wait,
    nonce: nonce,
    startFrom: startFromSequence,
  );

  /// Where the pod command counter stands, for the caller to persist.
  int get commandSequence => _commands.currentSequence;

  int get _nextSequence => _commands.nextSequence;

  /// Phase one: identify the pod, bind it to this controller, and prime it.
  ///
  /// Runs with the pod still off the body. Returns what the pod reported, which
  /// phase two needs.
  Future<PodActivationFacts> primePod({
    required PodActivationStep from,
  }) async {
    final facts = await _identifyPod(from);

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
      await reopenLink();
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
      await _insertCannula(facts);
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

  /// Drives the cannula in, but only once the user has confirmed it.
  ///
  /// The confirmation sits here rather than on the button that usually precedes
  /// it, so that every path into the insertion — a first run, a retry, a resume —
  /// passes through it. The step is recorded only after the command has gone out,
  /// so a decline leaves the activation exactly where it was.
  Future<void> _insertCannula(PodActivationFacts facts) async {
    if (!await confirmCannulaInsertion()) {
      throw PodActivationCancelled();
    }
    await _commands.deliverPulses(
      facts,
      facts.cannulaInsertionPulses,
      facts.uniqueId,
    );
    await onStep(PodActivationStep.insertingCannula);
    await wait(facts.deliveryTimeFor(facts.cannulaInsertionPulses));
    await reopenLink();
  }

  /// The pod's own numbers: read from it, or restored from an interrupted
  /// attempt once it is too late to ask again.
  ///
  /// Asking again is not an option past [PodActivationStep.identitySet]: the
  /// version read is addressed to the discovery id, which the pod stops answering
  /// on the moment it has an id of its own, and assigning that id is a one-shot
  /// command. So a resume that has no record simply cannot continue — better said
  /// plainly than sent to a pod that will never answer.
  Future<PodActivationFacts> _identifyPod(PodActivationStep from) async {
    if (!from.isBefore(PodActivationStep.identitySet)) {
      final known = knownFacts;
      if (known == null) {
        throw PodActivationException(
          'Resumed activation has no record of what the pod reported',
        );
      }
      return known;
    }
    final version = await _readVersion();
    final identity = await _setIdentity(version);
    final facts = PodActivationFacts(
      uniqueId: identity.uniqueId,
      lotNumber: version.lotNumber,
      podSequenceNumber: version.podSequenceNumber,
      primePulses: identity.primePulses,
      cannulaInsertionPulses: identity.cannulaInsertionPulses,
      primePumpRateEighthSeconds: identity.primePumpRateEighthSeconds,
      expirationHours: identity.expirationHours,
    );
    await onFacts(facts);
    return facts;
  }

  Future<PodVersionResponse> _readVersion() async {
    debugPrint('pod activation: -> getVersion');
    final response = await sendCommand(
      PodGetVersionCommand(sequenceNumber: _nextSequence),
    );
    debugPrint('pod activation: <- $response');
    if (response is! PodVersionResponse) {
      throw PodActivationException('Pod did not report its version: $response');
    }
    if (response.lifecycle == PodLifecycleStatus.alarm) {
      throw PodActivationException('Pod is already in alarm and cannot be used');
    }
    await onStep(PodActivationStep.gotVersion);
    return response;
  }

  Future<PodSetUniqueIdResponse> _setIdentity(PodVersionResponse version) async {
    debugPrint('pod activation: -> setUniqueId $podUniqueId');
    final response = await sendCommand(PodSetUniqueIdCommand(
      uniqueId: podUniqueId,
      sequenceNumber: _nextSequence,
      lotNumber: version.lotNumber,
      podSequenceNumber: version.podSequenceNumber,
      activatedAt: now(),
    ));
    debugPrint('pod activation: <- $response');
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

/// Thrown when the user declined the confirmation for the cannula insertion.
///
/// Distinct from [PodActivationException] because nothing went wrong: the pod is
/// untouched and the activation can simply be continued later.
class PodActivationCancelled implements Exception {
  @override
  String toString() => 'PodActivationCancelled';
}
