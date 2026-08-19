import 'dart:typed_data';
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
