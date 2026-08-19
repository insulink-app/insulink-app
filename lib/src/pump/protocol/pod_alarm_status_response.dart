import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_alarm.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

/// The alarm status page, read when a pod reports itself in alarm.
///
/// This is the only way to learn WHY a pod stopped. It repeats the routine status
/// fields and adds the alarm itself, plus the state the pod was in when it
/// happened — which matters because a pod that alarmed mid-bolus may have
/// delivered part of a dose the app believes it gave in full.
class PodAlarmStatusResponse extends PodResponse {
  PodAlarmStatusResponse(Uint8List body) {
    if (body.length < 24) {
      throw PodResponseException('Alarm status too short: ${body.length}');
    }
    final view = ByteData.view(body.buffer, body.offsetInBytes);
    lifecycle = PodLifecycleStatus.byValue(body[3] & 0x0f);
    delivery = PodDeliveryStatus.byValue(body[4] & 0x0f);
    bolusPulsesRemaining = view.getUint16(5) & 0x7FF;
    lastProgrammingSequenceNumber = body[7] & 0x0f;
    totalPulsesDelivered = view.getUint16(8);
    alarm = PodAlarm(body[10]);
    minutesSinceAlarm = view.getUint16(11);
    reservoirPulsesRemaining = view.getUint16(13);
    minutesSinceActivation = view.getUint16(15);
    activeAlerts = PodAlert.decode(body[17]);
    occlusionAlarm = body[18] & 0x01 != 0;
    pulseInfoInvalid = (body[18] >> 1) & 0x01 != 0;
    lifecycleWhenAlarmOccurred = PodLifecycleStatus.byValue(body[19] & 0x0f);
    bolusActiveWhenAlarmOccurred = (body[19] >> 4) & 0x01 != 0;
    occlusionType = (body[19] >> 5) & 0x03;
    rssi = body[20] & 0x3f;
  }

  late final PodLifecycleStatus lifecycle;
  late final PodDeliveryStatus delivery;
  late final int bolusPulsesRemaining;
  late final int lastProgrammingSequenceNumber;
  late final int totalPulsesDelivered;
  late final PodAlarm alarm;
  late final int minutesSinceAlarm;
  late final int reservoirPulsesRemaining;
  late final int minutesSinceActivation;
  late final Set<PodAlert> activeAlerts;

  /// The pod's dedicated occlusion flag, set alongside an occlusion alarm.
  late final bool occlusionAlarm;

  /// The pod could not trust its own pulse accounting, so
  /// [totalPulsesDelivered] may be wrong.
  late final bool pulseInfoInvalid;

  late final PodLifecycleStatus lifecycleWhenAlarmOccurred;

  /// Whether a bolus was running when the pod alarmed. When true, the dose the
  /// app recorded was probably not delivered in full.
  late final bool bolusActiveWhenAlarmOccurred;

  late final int occlusionType;
  late final int rssi;

  double get totalUnitsDelivered =>
      totalPulsesDelivered * PodBolusAmount.pulseUnits;

  /// Units left, or null while the pod reports more than it can measure.
  double? get reservoirUnits =>
      reservoirPulsesRemaining == PodStatusResponse.reservoirUnknown
          ? null
          : reservoirPulsesRemaining * PodBolusAmount.pulseUnits;

  /// Insulin that was still queued for a bolus when the pod stopped — the dose
  /// the body did NOT receive.
  double get undeliveredBolusUnits =>
      bolusPulsesRemaining * PodBolusAmount.pulseUnits;

  @override
  String toString() => 'PodAlarmStatusResponse($alarm, $lifecycle, '
      'undelivered=$undeliveredBolusUnits U, occlusion=$occlusionAlarm)';
}
