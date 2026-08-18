import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_crc.dart';

/// Which kind of delivery the interlock is guarding.
enum PodInsulinDeliveryType {
  basal(0x00),
  tempBasal(0x01),
  bolus(0x02);

  const PodInsulinDeliveryType(this.value);

  final int value;
}

/// The 0x1a command that always immediately precedes a delivery program.
///
/// It restates the same delivery the following command asks for, in a second
/// encoding and with an additive checksum over it, so the pod can cross-check a
/// delivery request against itself before acting. The two halves travel in one
/// frame and must agree — that redundancy is the pod's own safeguard against a
/// corrupted dose, and it is what the encoders' read-back checks lean on.
///
/// The three untyped fields carry different things per delivery type, which is
/// why they are named after their wire position rather than their meaning:
///  - bolus: slot count, pulses × pulse spacing, immediate pulses
///  - basal: current slot index, eighth-seconds left in it, pulses left in it
class PodInsulinInterlock {
  const PodInsulinInterlock({
    required this.nonce,
    required this.deliveryType,
    required this.checksum,
    required this.byte9,
    required this.byte10And11,
    required this.byte12And13,
    required this.elements,
  });

  final int nonce;
  final PodInsulinDeliveryType deliveryType;
  final int checksum;
  final int byte9;
  final int byte10And11;
  final int byte12And13;

  /// The packed 2-byte program elements the pod meters from.
  final List<Uint8List> elements;

  int get _elementBytes =>
      elements.fold<int>(0, (sum, element) => sum + element.length);

  int get bodyLength => _elementBytes + 12;

  Uint8List get encoded {
    final out = Uint8List(_elementBytes + 14);
    final view = ByteData.view(out.buffer);
    out[0] = PodCommandType.programInsulin.value;
    out[1] = bodyLength;
    view.setUint32(2, nonce & 0xFFFFFFFF);
    out[6] = deliveryType.value;
    view.setUint16(7, checksum);
    out[9] = byte9 & 0xFF;
    view.setUint16(10, byte10And11);
    view.setUint16(12, byte12And13);
    var offset = 14;
    for (final element in elements) {
      out.setRange(offset, offset + element.length, element);
      offset += element.length;
    }
    return out;
  }

  /// The additive checksum a bolus interlock carries: slot count, pulse
  /// spacing, and the pulse count twice.
  static int bolusChecksum({required int pulses, required int pulseSpacing}) {
    return PodAdditiveChecksum(<int>[
      0x01,
      (pulseSpacing >> 8) & 0xFF,
      pulseSpacing & 0xFF,
      (pulses >> 8) & 0xFF,
      pulses & 0xFF,
      (pulses >> 8) & 0xFF,
      pulses & 0xFF,
    ]).value;
  }

  /// The additive checksum a basal interlock carries: the current slot index,
  /// its remaining pulses and eighth-seconds, then every slot's pulse count.
  ///
  /// Note the order — pulses BEFORE eighth-seconds — is the reverse of how the
  /// same two values sit in the interlock body. That asymmetry is the pod's;
  /// swapping it produces a frame the pod rejects.
  static int basalChecksum({
    required int currentSlotIndex,
    required int pulsesRemaining,
    required int eighthSecondsRemaining,
    required List<int> pulsesPerSlot,
  }) {
    final bytes = <int>[
      currentSlotIndex & 0xFF,
      (pulsesRemaining >> 8) & 0xFF,
      pulsesRemaining & 0xFF,
      (eighthSecondsRemaining >> 8) & 0xFF,
      eighthSecondsRemaining & 0xFF,
    ];
    for (final pulses in pulsesPerSlot) {
      bytes
        ..add((pulses >> 8) & 0xFF)
        ..add(pulses & 0xFF);
    }
    return PodAdditiveChecksum(bytes).value;
  }
}
