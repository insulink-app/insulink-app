import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

/// Why a delivery was refused. Each case is a distinct thing to tell the user,
/// so the UI can say what to do rather than only that something failed.
enum PodDeliveryRefusal {
  podNotRunning,
  podAlarming,
  alreadyBolusing,
  notSuspendable,
  aboveUserLimit,
  aboveHourlyLimit,
  notEnoughInsulin,
  statusTooOld,
}

/// The outcome of checking a bolus before it is built into a command.
class PodDeliveryDecision {
  const PodDeliveryDecision.allowed() : refusal = null, detail = null;

  const PodDeliveryDecision.refused(this.refusal, this.detail);

  final PodDeliveryRefusal? refusal;
  final String? detail;

  bool get isAllowed => refusal == null;
}

/// The checks that run between a user asking for a bolus and a command being
/// built for it.
///
/// These sit ON TOP of the protocol limits in [PodBolusAmount], never instead
/// of them, and they are all refusals rather than clamps: silently delivering
/// less than the user asked for is its own kind of dosing error, so a request
/// that cannot be honoured exactly is rejected and shown, not trimmed.
///
/// The pod status this reads must be fresh. A decision made on a status from
/// ten minutes ago can miss a bolus that is still running, so [maxStatusAge]
/// is enforced here rather than left to the caller to remember.
class PodDeliveryGuard {
  const PodDeliveryGuard({
    required this.maxBolusUnits,
    required this.maxUnitsPerHour,
    this.maxStatusAge = const Duration(minutes: 2),
  });

  /// The user's own single-bolus ceiling, at or below the pod's.
  final double maxBolusUnits;

  /// A rolling one-hour ceiling across boluses, so a repeated tap or a retry
  /// loop cannot stack doses the user never intended.
  final double maxUnitsPerHour;

  final Duration maxStatusAge;

  /// Checks a requested bolus against the pod and the configured limits.
  ///
  /// [deliveredLastHour] is the sum of boluses already confirmed within the
  /// past hour; [statusAge] is how long ago [status] was read.
  PodDeliveryDecision checkBolus({
    required PodBolusAmount amount,
    required PodStatusResponse status,
    required Duration statusAge,
    required double deliveredLastHour,
  }) {
    if (statusAge > maxStatusAge) {
      return PodDeliveryDecision.refused(
        PodDeliveryRefusal.statusTooOld,
        'Pod status is ${statusAge.inMinutes} min old',
      );
    }
    if (status.lifecycle == PodLifecycleStatus.alarm) {
      return const PodDeliveryDecision.refused(
        PodDeliveryRefusal.podAlarming,
        'Pod is in alarm and must be replaced',
      );
    }
    if (!status.lifecycle.isRunning) {
      return PodDeliveryDecision.refused(
        PodDeliveryRefusal.podNotRunning,
        'Pod is ${status.lifecycle.name}',
      );
    }
    if (status.delivery.isBolusing) {
      return const PodDeliveryDecision.refused(
        PodDeliveryRefusal.alreadyBolusing,
        'A bolus is still running — cancel it first',
      );
    }
    if (amount.units > maxBolusUnits) {
      return PodDeliveryDecision.refused(
        PodDeliveryRefusal.aboveUserLimit,
        '${amount.units} U is above the configured maximum of $maxBolusUnits U',
      );
    }
    if (deliveredLastHour + amount.units > maxUnitsPerHour) {
      return PodDeliveryDecision.refused(
        PodDeliveryRefusal.aboveHourlyLimit,
        '${deliveredLastHour + amount.units} U in one hour is above $maxUnitsPerHour U',
      );
    }
    final reservoir = status.reservoirUnits;
    if (reservoir != null && amount.units > reservoir) {
      return PodDeliveryDecision.refused(
        PodDeliveryRefusal.notEnoughInsulin,
        'Only $reservoir U left in the reservoir',
      );
    }
    return const PodDeliveryDecision.allowed();
  }

  /// Whether a suspend-all is worth sending. Unlike a bolus this is allowed in
  /// almost every state — the one case it cannot help is a pod that has already
  /// stopped, and even then sending it is harmless.
  PodDeliveryDecision checkSuspend({required PodStatusResponse status}) {
    if (status.lifecycle == PodLifecycleStatus.deactivated) {
      return const PodDeliveryDecision.refused(
        PodDeliveryRefusal.notSuspendable,
        'Pod is already deactivated',
      );
    }
    return const PodDeliveryDecision.allowed();
  }
}
