import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_running_bolus.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_delivery_guard.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';

/// What became of a bolus the user confirmed.
enum BolusDeliveryStatus {
  /// No pump is involved — the user injects it themselves and the app records
  /// it, exactly as it did before pump support existed.
  loggedOnly,

  /// The pod confirmed it is delivering.
  delivered,

  /// The pod, or a guard in front of it, refused. No insulin was given.
  refused,

  /// The command went out but was never confirmed. The pod MAY be delivering.
  unknown,

  /// On its way to the pump, with the answer still to come. The page does not
  /// wait for it — the overview reports what became of it.
  handedOver,
}

/// The outcome of a bolus, and how many units may be recorded because of it.
class BolusDeliveryResult {
  const BolusDeliveryResult._(this.status, this.recordedUnits, this.detail);

  const BolusDeliveryResult.loggedOnly(double units)
    : this._(BolusDeliveryStatus.loggedOnly, units, null);

  const BolusDeliveryResult.delivered(double units)
    : this._(BolusDeliveryStatus.delivered, units, null);

  /// Nothing was delivered, so nothing is recorded as insulin.
  const BolusDeliveryResult.refused(String detail)
    : this._(BolusDeliveryStatus.refused, 0, detail);

  /// The outcome is genuinely unknown. Zero units are recorded — understating
  /// insulin is recoverable by logging it afterwards, whereas overstating it
  /// would suppress a later dose the user actually needs.
  const BolusDeliveryResult.unknown(String detail)
    : this._(BolusDeliveryStatus.unknown, 0, detail);

  /// Handed to the pump; the sheet is free to close. The meal is written with its
  /// carbs and no insulin, and the dose is added only once the pod names it back.
  const BolusDeliveryResult.handedOver()
    : this._(BolusDeliveryStatus.handedOver, 0, null);

  final BolusDeliveryStatus status;

  /// Units that may be written to the meal log.
  final double recordedUnits;

  /// Why it failed, for the message shown next to the retry.
  final String? detail;

  bool get isDelivered => status == BolusDeliveryStatus.delivered;

  bool get needsAttention =>
      status == BolusDeliveryStatus.refused ||
      status == BolusDeliveryStatus.unknown;

  bool get byPump =>
      status == BolusDeliveryStatus.delivered ||
      status == BolusDeliveryStatus.handedOver;

  /// Whether the pump still owes an answer, so the caller hands over rather than
  /// waits.
  bool get isPending => status == BolusDeliveryStatus.handedOver;
}

/// Decides whether a confirmed bolus goes to a pump or is only logged, and
/// carries it out.
///
/// When no pod is paired this reports [BolusDeliveryStatus.loggedOnly] and the
/// app behaves exactly as it did before — the user gives the injection and the
/// app records it.
///
/// The rule about what gets recorded is deliberately one-directional: insulin is
/// only ever written to the log once the pod has confirmed it. A dose that was
/// refused, or whose fate is unknown, records nothing and says so. Recording
/// insulin that was never given would suppress the next dose through IOB, which
/// is the more dangerous mistake of the two.
class BolusDelivery {
  const BolusDelivery({
    required this.controller,
    required this.maxBolusUnits,
    required this.maxUnitsPerHour,
  });

  final PodController controller;

  /// The user's configured single-bolus ceiling (`ProfileBolusState.maxBolus`).
  final double maxBolusUnits;

  /// The rolling one-hour ceiling, so repeated taps cannot stack doses.
  final double maxUnitsPerHour;

  /// Whether this bolus will be sent to a pod rather than only logged.
  bool get usesPump => controller.hasPod;

  /// Runs the bolus. [deliveredLastHour] is the insulin already given within the
  /// past hour, which the rolling limit is checked against.
  Future<BolusDeliveryResult> deliver(
    double units, {
    required double deliveredLastHour,
  }) async {
    if (!usesPump || units <= 0) {
      return BolusDeliveryResult.loggedOnly(units);
    }
    final PodBolusAmount amount;
    try {
      amount = PodBolusAmount.fromUnits(units);
    } on PodDoseException catch (error) {
      return BolusDeliveryResult.refused(error.message);
    }

    // Recorded before anything is sent, so a process that dies between here and
    // the pod's answer leaves evidence that a dose may be running.
    await controller.store.startPendingBolus(
      PodRunningBolus(
        startedAt: DateTime.now(),
        pulses: amount.pulses,
        eighthSecondsBetweenPulses:
            PodProgramBolusCommand.defaultEighthSecondsBetweenPulses,
      ),
    );
    try {
      return await _send(amount, deliveredLastHour);
    } finally {
      await controller.store.clearPendingBolus();
    }
  }

  /// An outcome nobody can resolve, noted where the automation will find it.
  ///
  /// Zero units still reach the meal log, because the user can log the dose
  /// themselves once they have looked at the pod and inventing it for them would
  /// suppress a correction they may need. The automation cannot look at the pod
  /// and cannot ask, so it gets the opposite assumption: the dose was given. The
  /// insulin it is allowed to add is computed from what is already on board, and
  /// a loop blind to a dose that did go in would add on top of it.
  Future<BolusDeliveryResult> _unknown(
    String message,
    PodBolusAmount amount,
  ) async {
    await controller.store.recordUnconfirmedBolus(
      PodDelivery(
        at: DateTime.now(),
        units: amount.units,
        kind: PodDeliveryKind.bolus,
      ),
    );
    return BolusDeliveryResult.unknown(message);
  }

  /// Whether the pod's answer actually shows the bolus it was just given.
  ///
  /// A reply is not agreement. The pod answers a command sequence number it has
  /// already run by re-sending the ANSWER it gave the first time — so a counter
  /// that drifted out of step (the app and the background poll racing for the same
  /// number) reads as a perfectly well-formed status while no insulin moves. That
  /// is the one failure mode that would have the app record a dose the user never
  /// got, so the answer has to name the bolus, not merely arrive.
  bool _confirmsBolus(PodStatusResponse status) =>
      status.delivery.isBolusing || status.bolusPulsesRemaining > 0;

  /// Why this dose must not go out, judged against the state the pod reported
  /// moments earlier ON THE SAME LINK, or null when it may.
  ///
  /// The status carries no age here by construction: it was read on the very link
  /// that is about to carry the dose, so there is no window in which the pod could
  /// change underneath the decision. That used to cost a second BLE session, and
  /// the pod hung up on it.
  String? _refusalFor(
    PodBolusAmount amount,
    PodStatusResponse status,
    double deliveredLastHour,
  ) {
    final decision =
        PodDeliveryGuard(
          maxBolusUnits: maxBolusUnits,
          maxUnitsPerHour: maxUnitsPerHour,
        ).checkBolus(
          amount: amount,
          status: status,
          statusAge: Duration.zero,
          deliveredLastHour: deliveredLastHour,
        );
    if (decision.isAllowed) {
      return null;
    }
    return decision.detail ?? decision.refusal!.name;
  }

  /// Sends the programmed bolus and maps the pod's answer onto an outcome.
  Future<BolusDeliveryResult> _send(
    PodBolusAmount amount,
    double deliveredLastHour,
  ) async {
    try {
      final response = await controller.sendBolus(
        amount,
        refuseIf: (status) => _refusalFor(amount, status, deliveredLastHour),
      );
      if (response is PodNakResponse) {
        return BolusDeliveryResult.refused(
          'Pod refused it: ${response.error.name}',
        );
      }
      if (response is! PodStatusResponse) {
        return _unknown('The pod gave an unclear answer', amount);
      }
      if (!_confirmsBolus(response)) {
        return _unknown(
          'The pod answered but does not report a bolus running',
          amount,
        );
      }
      // Logged only once the pod has named the bolus back, never before: an entry
      // for a dose that did not run would overstate the insulin on board.
      final startedAt = DateTime.now();
      await controller.store.recordDelivery(
        PodDelivery(
          at: startedAt,
          units: amount.units,
          kind: PodDeliveryKind.bolus,
        ),
      );
      // The pod takes about two seconds per 0.05 U pulse, so this dose is still
      // running for a while. Recorded so the overview can show it and stop it.
      await controller.store.startRunningBolus(
        PodRunningBolus(
          startedAt: startedAt,
          pulses: amount.pulses,
          eighthSecondsBetweenPulses:
              PodProgramBolusCommand.defaultEighthSecondsBetweenPulses,
        ),
      );
      controller.notifyRunningBolusChanged();
      return BolusDeliveryResult.delivered(amount.units);
    } on PodBolusRefused catch (refusal) {
      return BolusDeliveryResult.refused(refusal.reason);
    } on PodCommandOutcomeUnknown catch (error) {
      return _unknown(error.message, amount);
    } on Exception catch (error) {
      return BolusDeliveryResult.refused('$error');
    }
  }
}
