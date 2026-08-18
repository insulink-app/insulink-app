import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_delivery_gate.dart';
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

  final BolusDeliveryStatus status;

  /// Units that may be written to the meal log.
  final double recordedUnits;

  /// Why it failed, for the message shown next to the retry.
  final String? detail;

  bool get isDelivered => status == BolusDeliveryStatus.delivered;

  bool get needsAttention =>
      status == BolusDeliveryStatus.refused ||
      status == BolusDeliveryStatus.unknown;

  bool get byPump => status == BolusDeliveryStatus.delivered;
}

/// Decides whether a confirmed bolus goes to a pump or is only logged, and
/// carries it out.
///
/// When no pod is paired, or the delivery gate is shut, this reports
/// [BolusDeliveryStatus.loggedOnly] and the app behaves exactly as it did
/// before — the user gives the injection and the app records it.
///
/// The rule about what gets recorded is deliberately one-directional: insulin is
/// only ever written to the log once the pod has confirmed it. A dose that was
/// refused, or whose fate is unknown, records nothing and says so. Recording
/// insulin that was never given would suppress the next dose through IOB, which
/// is the more dangerous mistake of the two.
class BolusDelivery {
  const BolusDelivery({
    required this.controller,
    required this.gate,
    required this.maxBolusUnits,
    required this.maxUnitsPerHour,
  });

  final PodController controller;
  final PodDeliveryGate gate;

  /// The user's configured single-bolus ceiling (`ProfileBolusState.maxBolus`).
  final double maxBolusUnits;

  /// The rolling one-hour ceiling, so repeated taps cannot stack doses.
  final double maxUnitsPerHour;

  /// Whether this bolus will be sent to a pod rather than only logged.
  bool get usesPump => controller.hasPod && gate.allowsDelivery;

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

    await controller.refresh();
    final status = controller.status;
    final readAt = controller.statusReadAt;
    if (status == null || readAt == null) {
      return BolusDeliveryResult.refused(
        controller.failure ?? 'Could not read the pod',
      );
    }

    final decision = PodDeliveryGuard(
      maxBolusUnits: maxBolusUnits,
      maxUnitsPerHour: maxUnitsPerHour,
    ).checkBolus(
      amount: amount,
      status: status,
      statusAge: DateTime.now().difference(readAt),
      deliveredLastHour: deliveredLastHour,
    );
    if (!decision.isAllowed) {
      return BolusDeliveryResult.refused(
        decision.detail ?? decision.refusal!.name,
      );
    }
    return _send(amount);
  }

  /// Sends the programmed bolus and maps the pod's answer onto an outcome.
  Future<BolusDeliveryResult> _send(PodBolusAmount amount) async {
    try {
      final response = await controller.sendBolus(amount);
      if (response is PodNakResponse) {
        return BolusDeliveryResult.refused('Pod refused it: ${response.error.name}');
      }
      if (response is! PodStatusResponse) {
        return const BolusDeliveryResult.unknown('The pod gave an unclear answer');
      }
      return BolusDeliveryResult.delivered(amount.units);
    } on PodCommandOutcomeUnknown catch (error) {
      return BolusDeliveryResult.unknown(error.message);
    } on Exception catch (error) {
      return BolusDeliveryResult.refused('$error');
    }
  }
}
