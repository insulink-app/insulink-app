import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_stop_delivery_command.dart';

/// The beep nibble sits in the high half of the last body byte, before the CRC.
PodBeep beepOf(PodCommand command) {
  final frame = command.encoded;
  return PodBeep.values.firstWhere(
    (beep) => beep.value == (frame[frame.length - 3] >> 4),
    orElse: () => PodBeep.silent,
  );
}

void main() {
  PodStopDeliveryCommand stop({required PodBeep beep}) =>
      PodStopDeliveryCommand(
        uniqueId: 0x1091,
        sequenceNumber: 1,
        nonce: podFixedNonce,
        target: PodDeliveryTarget.tempBasal,
        beep: beep,
      );

  test('the beep the caller asked for is what reaches the pod', () {
    expect(beepOf(stop(beep: PodBeep.silent)), PodBeep.silent);
    expect(beepOf(stop(beep: PodBeep.longSingleBeep)), PodBeep.longSingleBeep);
  });

  /// A stop beeps by default so the user can hear the pod act, which is right
  /// when a person asked for it.
  test('a stop beeps unless told otherwise', () {
    final command = PodStopDeliveryCommand(
      uniqueId: 0x1091,
      sequenceNumber: 1,
      nonce: podFixedNonce,
      target: PodDeliveryTarget.tempBasal,
    );

    expect(beepOf(command), PodBeep.longSingleBeep);
  });
}
