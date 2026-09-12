import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';

/// Which deliveries to stop. The bits are independent, so [all] is the
/// suspend-everything case used by the emergency stop.
enum PodDeliveryTarget {
  basal(0x01),
  tempBasal(0x02),
  bolus(0x04),
  all(0x07);

  const PodDeliveryTarget(this.bits);

  final int bits;
}

/// Stops insulin delivery — cancelling a running bolus, a temp basal, the
/// basal, or everything at once.
///
/// This is the command that has to work when nothing else does, so it is kept
/// deliberately small and free of any computed dose: there is no number here
/// that could be wrong, only which streams to halt. Nothing in the app may gate
/// it behind a confirmation step that could fail closed.
class PodStopDeliveryCommand extends PodCommand {
  PodStopDeliveryCommand({
    required super.uniqueId,
    required super.sequenceNumber,
    required this.nonce,
    required this.target,
    this.beep = PodBeep.longSingleBeep,
    super.multiCommand,
  });

  /// The emergency stop: halt every kind of delivery, with the audible
  /// confirmation on, so the user can hear that the pod acted.
  factory PodStopDeliveryCommand.suspendAll({
    required int uniqueId,
    required int sequenceNumber,
    required int nonce,
  }) {
    return PodStopDeliveryCommand(
      uniqueId: uniqueId,
      sequenceNumber: sequenceNumber,
      nonce: nonce,
      target: PodDeliveryTarget.all,
      beep: PodBeep.longSingleBeep,
    );
  }

  /// Cancels a running bolus and leaves basal alone.
  factory PodStopDeliveryCommand.cancelBolus({
    required int uniqueId,
    required int sequenceNumber,
    required int nonce,
  }) {
    return PodStopDeliveryCommand(
      uniqueId: uniqueId,
      sequenceNumber: sequenceNumber,
      nonce: nonce,
      target: PodDeliveryTarget.bolus,
      beep: PodBeep.longSingleBeep,
    );
  }

  final int nonce;
  final PodDeliveryTarget target;
  final PodBeep beep;

  @override
  PodCommandType get type => PodCommandType.stopDelivery;

  @override
  Uint8List get encoded => appendCrc(
    joinParts([
      buildHeader(7),
      [type.value, 0x05],
      bigEndian32(nonce),
      [((beep.value << 4) | target.bits) & 0xFF],
    ]),
  );
}
