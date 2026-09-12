import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_basal_elements.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_insulin_interlock.dart';

/// Programs the pod's 24-hour basal schedule.
///
/// The schedule is absolute, not relative: it says what to deliver in each of
/// the day's 48 half-hour slots, and the pod picks up mid-slot from [now]. So
/// [now] has to be the real local time — a wrong clock shifts the whole
/// schedule, and the pod has no way to notice.
///
/// Sending this replaces whatever basal the pod was running. It does not resume
/// a suspended pod on its own.
class PodProgramBasalCommand extends PodCommand {
  PodProgramBasalCommand({
    required super.uniqueId,
    required super.sequenceNumber,
    required this.nonce,
    required this.program,
    required this.now,
    this.reminder = const PodProgramReminder(),
    super.multiCommand,
  }) : _elements = PodBasalElements(program);

  final int nonce;
  final PodBasalProgram program;
  final DateTime now;
  final PodProgramReminder reminder;

  final PodBasalElements _elements;

  @override
  PodCommandType get type => PodCommandType.programBasal;

  @override
  Uint8List get encoded {
    final interlock = _interlock.encoded;
    final body = _basalBody;
    return appendCrc(
      joinParts([buildHeader(interlock.length + body.length), interlock, body]),
    );
  }

  PodInsulinInterlock get _interlock {
    final slot = program.currentSlotAt(now);
    return PodInsulinInterlock(
      nonce: nonce,
      deliveryType: PodInsulinDeliveryType.basal,
      checksum: PodInsulinInterlock.basalChecksum(
        currentSlotIndex: slot.index,
        pulsesRemaining: slot.pulsesRemaining,
        eighthSecondsRemaining: slot.eighthSecondsRemaining,
        pulsesPerSlot: program.pulsesPerSlot,
      ),
      byte9: slot.index,
      byte10And11: slot.eighthSecondsRemaining,
      byte12And13: slot.pulsesRemaining,
      elements: [
        for (final element in _elements.shortElements) element.encoded,
      ],
    );
  }

  Uint8List get _basalBody {
    final longElements = _elements.longElements;
    final current = _elements.currentLongElementAt(now);
    return joinParts([
      [type.value, longElements.length * 6 + 8],
      reminder.encoded,
      [current.index & 0xFF],
      bigEndian16(current.remainingTenthPulses),
      bigEndian32(current.delayUntilNextTenthPulseUsec),
      for (final element in longElements) element.encoded,
    ]);
  }
}
