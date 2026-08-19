import 'package:insulink/src/pump/protocol/pod_activation_state.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_control_commands.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

/// The command plumbing an activation runs on: sequence numbering, the two
/// deliveries, and waiting for the pod to finish one.
///
/// Split from [PodActivation] so the sequence of steps reads as a sequence, with
/// the "send this and insist on a sensible answer" mechanics out of the way.
class PodActivationCommands {
  PodActivationCommands({
    required this.sendCommand,
    required this.wait,
    required this.nonce,
    int startFrom = 0,
  }) : _sequence = startFrom & 0x0f;

  static const int _maxStatusPolls = 20;
  static const Duration _statusPollInterval = Duration(seconds: 3);

  final Future<PodResponse> Function(PodCommand command) sendCommand;
  final Future<void> Function(Duration duration) wait;

  /// The fixed nonce the delivery commands carry.
  final int nonce;

  int _sequence;

  /// Where the counter stands, so the caller can persist it. The pod refuses a
  /// number it has already run, so an activation that did not hand its counter on
  /// would have the next command collide with one of its own.
  int get currentSequence => _sequence;

  /// The next pod command sequence number, wrapping inside the 4 bits the wire
  /// gives it.
  int get nextSequence {
    _sequence = (_sequence + 1) & 0x0f;
    return _sequence;
  }

  /// Sends a prime or cannula-insertion bolus of exactly [pulses].
  ///
  /// The volume comes from the pod, so it is converted through
  /// [PodBolusAmount.fromPulses] rather than through units — no rounding step is
  /// introduced between what the pod asked for and what is programmed.
  Future<void> deliverPulses(
    PodActivationFacts facts,
    int pulses,
    int uniqueId,
  ) async {
    await expectStatus(PodProgramBolusCommand(
      uniqueId: uniqueId,
      sequenceNumber: nextSequence,
      nonce: nonce,
      amount: PodBolusAmount.fromPulses(pulses),
      eighthSecondsBetweenPulses: facts.primePumpRateEighthSeconds,
    ));
  }

  /// Polls until the pod has finished whatever it was delivering.
  Future<PodStatusResponse> awaitDeliveryIdle(int uniqueId, String what) async {
    for (var attempt = 0; attempt < _maxStatusPolls; attempt++) {
      final status = await _readStatus(uniqueId);
      if (status.lifecycle == PodLifecycleStatus.alarm) {
        throw PodActivationException('Pod alarmed during $what');
      }
      if (status.bolusPulsesRemaining == 0 &&
          status.lifecycle != PodLifecycleStatus.priming) {
        return status;
      }
      await wait(_statusPollInterval);
    }
    throw PodActivationException('Pod did not finish $what in time');
  }

  Future<PodStatusResponse> _readStatus(int uniqueId) async {
    final response = await sendCommand(
      PodGetStatusCommand(uniqueId: uniqueId, sequenceNumber: nextSequence),
    );
    if (response is PodStatusResponse) {
      return response;
    }
    throw PodActivationException('Expected a status, got $response');
  }

  /// Runs a command that should be answered with a status, turning a refusal into
  /// a clear failure instead of letting activation continue past it.
  Future<PodStatusResponse> expectStatus(PodCommand command) async {
    final response = await sendCommand(command);
    if (response is PodStatusResponse) {
      return response;
    }
    if (response is PodNakResponse) {
      throw PodActivationException(
        'Pod refused ${command.type.name}: ${response.error.name}',
      );
    }
    throw PodActivationException(
      'Unexpected reply to ${command.type.name}: $response',
    );
  }
}
