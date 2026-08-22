import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/pod_basal_delivery.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_control_commands.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/protocol/pod_stop_delivery_command.dart';
import 'package:insulink/src/pump/protocol/pod_temp_basal_command.dart';

/// The four things the automation ever asks a pod to do, and the counter
/// bookkeeping each of them needs.
///
/// Split from the runner so that file is only policy: what to deliver and when
/// to stop. Nothing here decides anything.
///
/// Every command advances the pod's 4-bit sequence counter, which is persisted
/// BEFORE the reply is awaited. The pod refuses a number it has already run, so
/// a number used but not stored is the failure this ordering exists to prevent.
class LoopPodCommands {
  const LoopPodCommands({
    required this.store,
    required this.session,
    required this.now,
  });

  final PodStore store;
  final PodSession session;
  final DateTime Function() now;

  /// Reads the pod's state. Throws when the pod answers with anything else,
  /// because a decision made on a non-answer is a decision made on nothing.
  Future<PodStatusResponse> readStatus() async {
    final response = await _run(
      (sequence) => PodGetStatusCommand(
        uniqueId: store.uniqueId!,
        sequenceNumber: sequence,
        page: PodStatusPage.defaultPage,
      ),
    );
    if (response is! PodStatusResponse) {
      throw StateError('pod answered a status request with $response');
    }
    await store.saveLastStatus(response, now());
    return response;
  }

  /// Programs [unitsPerHour] for one fuse and records the stretch it covers.
  ///
  /// The stretch is stored BEFORE the command goes out. A confirmation lost in
  /// transit then leaves the ledger crediting this rate rather than the schedule,
  /// which overstates insulin when the rate is the higher of the two. That is the
  /// direction to fail in: an overstated insulin-on-board makes the next cycle
  /// ask for LESS, while understating it would make the next cycle ask for more
  /// on the strength of insulin that was in fact delivered.
  ///
  /// No end-of-delivery beep. A cycle runs every five minutes.
  ///
  /// A pod that REFUSES the command has the stored stretch rolled back, because
  /// the pod is then still on whatever it was running and the store would
  /// otherwise describe a rate that does not exist. An outcome that is merely
  /// unknown is left standing: the pod may well be running it, and that is the
  /// reading to keep.
  ///
  /// [running] is what the POD said it was delivering when this cycle read it.
  /// A temporary rate already in progress is ended before the new one goes out,
  /// here rather than at the call site: the pod holds ONE basal delivery, and a
  /// program landing on a running one is what faulted a pod when a basal
  /// SCHEDULE was sent that way. Leaving the step to the caller is how that
  /// happened, so neither of the two paths that program a rate can now skip it.
  Future<void> programTempBasal(
    double unitsPerHour, {
    required bool running,
  }) async {
    if (running) {
      await cancelTempBasal();
    }
    final rate = PodTempBasalRate(
      unitsPerHour: unitsPerHour,
      minutes: LoopLimits.fuse.inMinutes,
    );
    final previous = store.temporaryBasal;
    final startedAt = now();
    await store.saveTemporaryBasal(PodTemporaryBasal(
      unitsPerHour: rate.unitsPerHour,
      start: startedAt,
      end: startedAt.add(LoopLimits.fuse),
      automated: true,
    ));
    try {
      await _run(
        (sequence) => PodProgramTempBasalCommand(
          uniqueId: store.uniqueId!,
          sequenceNumber: sequence,
          nonce: podFixedNonce,
          rate: rate,
          reminder: const PodProgramReminder(),
        ),
      );
    } on LoopCommandRefused {
      await _restore(previous);
      rethrow;
    }
  }

  Future<void> _restore(PodTemporaryBasal? previous) async {
    if (previous == null) {
      await store.clearTemporaryBasal();
      return;
    }
    await store.saveTemporaryBasal(previous);
  }

  /// Ends the running temporary rate, putting the pod back on its own schedule.
  ///
  /// Silent, unlike every other stop in the app. A cancel beeps by default so the
  /// user can hear that the pod acted, which is right when a person asked for it.
  /// The automation replaces its rate every five minutes and each replacement
  /// cancels the last, so the same default is a beep twelve times an hour, all
  /// night. A sound that means "something happened" stops meaning anything when
  /// nothing has.
  Future<void> cancelTempBasal() async {
    await _run(
      (sequence) => PodStopDeliveryCommand(
        uniqueId: store.uniqueId!,
        sequenceNumber: sequence,
        nonce: podFixedNonce,
        target: PodDeliveryTarget.tempBasal,
        beep: PodBeep.silent,
      ),
    );
    final running = store.temporaryBasal;
    if (running != null) {
      await store.saveTemporaryBasal(running.endedAt(now()));
    }
  }

  /// Sends one command and refuses to treat a rejection as success.
  ///
  /// The pod answers a command it will not run with a NAK, which arrives as a
  /// perfectly ordinary response rather than an exception. Without this check
  /// the automation would record every refusal as delivered.
  ///
  /// That matters most in the direction that looks harmless. A refused rate
  /// ABOVE the schedule only leaves the store overstating insulin, which makes
  /// the next cycle ask for less. A refused SUSPENSION leaves the app believing
  /// delivery stopped while the pod carries on down its schedule, which is the
  /// one belief this feature may not hold wrongly.
  Future<PodResponse> _run(PodCommand Function(int sequence) build) async {
    final sequence = (store.commandSequence + 1) & 0x0f;
    final response = await session.run(build(sequence));
    await store.saveCommandSequence(sequence);
    if (response is PodNakResponse) {
      throw LoopCommandRefused(response.error.name);
    }
    return response;
  }
}

/// Thrown when the pod answered a command with a refusal.
///
/// Distinct from a failure: the pod was reached, understood the command and
/// declined it, so nothing was delivered and nothing about the pod changed.
class LoopCommandRefused implements Exception {
  LoopCommandRefused(this.reason);

  final String reason;

  @override
  String toString() => 'LoopCommandRefused: $reason';
}
