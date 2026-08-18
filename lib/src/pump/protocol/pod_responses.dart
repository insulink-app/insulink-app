import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_alarm.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';

/// Raised when a decrypted pod reply cannot be read.
class PodResponseException implements Exception {
  PodResponseException(this.message);

  final String message;

  @override
  String toString() => 'PodResponseException: $message';
}

/// Anything the pod sends back.
abstract class PodResponse {
  const PodResponse();
}

/// The pod's routine status: what it is delivering, how far into its life it
/// is, and how much insulin is left.
class PodStatusResponse extends PodResponse {
  PodStatusResponse(Uint8List body) {
    if (body.length < 10) {
      throw PodResponseException('Status response too short: ${body.length}');
    }
    final view = ByteData.view(body.buffer, body.offsetInBytes);
    final head = view.getUint32(2);
    final tail = view.getUint32(6);
    lifecycle = PodLifecycleStatus.byValue(body[1] & 0x0f);
    delivery = PodDeliveryStatus.byValue((body[1] >> 4) & 0x0f);
    totalPulsesDelivered = (head >> 15) & 0x1FFF;
    lastProgrammingSequenceNumber = (head >> 11) & 0x0F;
    bolusPulsesRemaining = head & 0x7FF;
    activeAlerts = PodAlert.decode((tail >> 23) & 0xFF);
    minutesSinceActivation = (tail >> 10) & 0x1FFF;
    reservoirPulsesRemaining = tail & 0x3FF;
  }

  /// The value the pod reports while the reservoir still holds more than it
  /// measures precisely. Treat it as "plenty", never as a number.
  static const int reservoirUnknown = 0x3FF;

  late final PodLifecycleStatus lifecycle;
  late final PodDeliveryStatus delivery;
  late final int totalPulsesDelivered;
  late final int lastProgrammingSequenceNumber;
  late final int bolusPulsesRemaining;
  late final Set<PodAlert> activeAlerts;
  late final int minutesSinceActivation;
  late final int reservoirPulsesRemaining;

  double get totalUnitsDelivered => totalPulsesDelivered * PodBolusAmount.pulseUnits;

  double get bolusUnitsRemaining => bolusPulsesRemaining * PodBolusAmount.pulseUnits;

  /// Units left in the reservoir, or null while the pod reports "plenty".
  double? get reservoirUnits => reservoirPulsesRemaining == reservoirUnknown
      ? null
      : reservoirPulsesRemaining * PodBolusAmount.pulseUnits;

  Duration get age => Duration(minutes: minutesSinceActivation);

  @override
  String toString() => 'PodStatusResponse($lifecycle, $delivery, '
      'reservoir=$reservoirUnits U, age=$age, alerts=$activeAlerts)';
}

/// The reply to a version request, sent by a pod that is not yet activated.
class PodVersionResponse extends PodResponse {
  PodVersionResponse(Uint8List body) {
    if (body.length < 23) {
      throw PodResponseException('Version response too short: ${body.length}');
    }
    final view = ByteData.view(body.buffer, body.offsetInBytes);
    firmwareVersion = '${body[2]}.${body[3]}.${body[4]}';
    bleVersion = '${body[5]}.${body[6]}.${body[7]}';
    productId = body[8];
    lifecycle = PodLifecycleStatus.byValue(body[9] & 0x0f);
    lotNumber = view.getUint32(10);
    podSequenceNumber = view.getUint32(14);
    rssi = body[18] & 0x3f;
    uniqueId = view.getUint32(19);
  }

  late final String firmwareVersion;
  late final String bleVersion;
  late final int productId;
  late final PodLifecycleStatus lifecycle;
  late final int lotNumber;
  late final int podSequenceNumber;
  late final int rssi;
  late final int uniqueId;

  @override
  String toString() => 'PodVersionResponse(fw=$firmwareVersion, ble=$bleVersion, '
      'lot=$lotNumber, seq=$podSequenceNumber, $lifecycle)';
}

/// The reply confirming the pod accepted its unique id, carrying the pump
/// constants the pod will meter with.
class PodSetUniqueIdResponse extends PodResponse {
  PodSetUniqueIdResponse(Uint8List body) {
    if (body.length < 29) {
      throw PodResponseException('Set-id response too short: ${body.length}');
    }
    final view = ByteData.view(body.buffer, body.offsetInBytes);
    pulseVolumeTenThousandthMicroLitre = view.getUint16(2);
    pumpRateEighthSeconds = body[4];
    primePumpRateEighthSeconds = body[5];
    cannulaInsertionPulses = body[6];
    primePulses = body[7];
    expirationHours = body[8];
    firmwareVersion = '${body[9]}.${body[10]}.${body[11]}';
    lifecycle = PodLifecycleStatus.byValue(body[16]);
    lotNumber = view.getUint32(17);
    podSequenceNumber = view.getUint32(21);
    uniqueId = view.getUint32(25);
  }

  late final int pulseVolumeTenThousandthMicroLitre;

  /// Pulse spacing for a normal bolus, in eighths of a second.
  late final int pumpRateEighthSeconds;

  /// Pulse spacing the pod wants for priming and cannula insertion.
  late final int primePumpRateEighthSeconds;

  /// Pulses the pod asks for to seat the cannula. Pod-reported, never guessed —
  /// this delivers insulin.
  late final int cannulaInsertionPulses;

  /// Pulses the pod asks for to prime itself. Pod-reported, never guessed.
  late final int primePulses;
  late final int expirationHours;
  late final String firmwareVersion;
  late final PodLifecycleStatus lifecycle;
  late final int lotNumber;
  late final int podSequenceNumber;
  late final int uniqueId;

  @override
  String toString() => 'PodSetUniqueIdResponse(id=$uniqueId, lot=$lotNumber, $lifecycle)';
}

/// The pod refusing a command, and why.
///
/// [PodNakError.illegalSecurityCode] means our command sequence drifted out of
/// step with the pod's; it carries [resyncCount] instead of an alarm and must
/// be handled by resyncing, never by blindly resending the command.
class PodNakResponse extends PodResponse {
  PodNakResponse(Uint8List body) {
    if (body.length < 5) {
      throw PodResponseException('NAK response too short: ${body.length}');
    }
    error = PodNakError.byValue(body[2]);
    if (error == PodNakError.illegalSecurityCode) {
      resyncCount = (body[3] << 8) | body[4];
      lifecycle = null;
    } else {
      resyncCount = 0;
      lifecycle = PodLifecycleStatus.byValue(body[4]);
    }
  }

  late final PodNakError error;
  late final int resyncCount;
  late final PodLifecycleStatus? lifecycle;

  @override
  String toString() => 'PodNakResponse($error, lifecycle=$lifecycle, resync=$resyncCount)';
}

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
