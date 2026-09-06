import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_crc.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_insulin_interlock.dart';

/// Raised when a requested dose cannot be represented exactly, exceeds a limit,
/// or does not survive the encoder's own read-back check.
class PodDoseException implements Exception {
  PodDoseException(this.message);

  final String message;

  @override
  String toString() => 'PodDoseException: $message';
}

/// A bolus amount that has been proven to be deliverable exactly.
///
/// The pod meters insulin in 0.05 U pulses and the wire format carries a pulse
/// COUNT, not units — so the conversion is where a dosing error would hide. The
/// dose is therefore carried as an integer pulse count from the first moment
/// and never as a double again: a value that is not a whole number of pulses is
/// refused here rather than silently rounded onto the user.
class PodBolusAmount {
  PodBolusAmount._(this.pulses);

  /// Builds an amount from units, refusing anything not exactly on the 0.05 U
  /// grid. Rounding a user's 1.03 U down to 1.00 U silently is a dosing error,
  /// so the caller has to present a value the pod can actually deliver.
  factory PodBolusAmount.fromUnits(double units) {
    if (units.isNaN || units.isInfinite) {
      throw PodDoseException('Bolus is not a number');
    }
    if (units <= 0) {
      throw PodDoseException('Bolus must be greater than zero, got $units U');
    }
    final hundredths = (units * 100).round();
    if ((hundredths / 100 - units).abs() > 1e-9) {
      throw PodDoseException('Bolus $units U is not a whole number of 0.01 U');
    }
    if (hundredths % unitHundredthsPerPulse != 0) {
      throw PodDoseException(
        'Bolus $units U is not a multiple of the pod\'s $pulseUnits U pulse',
      );
    }
    return PodBolusAmount.fromPulses(hundredths ~/ unitHundredthsPerPulse);
  }

  /// [units] snapped DOWN onto the pod's pulse grid, so a computed dose can be
  /// delivered as it stands.
  ///
  /// The bolus calculator works in real numbers and routinely lands on something
  /// like 1.01502045 U, which [PodBolusAmount.fromUnits] refuses — correctly, it
  /// is not a dose the pod can meter. The injection sheet never hit that because
  /// the user reads the number off a field rounded to one decimal; a dose carried
  /// out straight from a notification has no such field, so it is snapped here.
  ///
  /// DOWN rather than to nearest, because nobody is looking at this number. Half
  /// a pulse (0.025 U) less than the calculation asked for is nothing; half a
  /// pulse more is insulin it did not ask for.
  static double snapToPulse(double units) {
    if (units.isNaN || units.isInfinite || units <= 0) {
      return 0;
    }
    return ((units * 100) / unitHundredthsPerPulse).floor() * pulseUnits;
  }

  /// Builds an amount from a pulse count.
  factory PodBolusAmount.fromPulses(int pulses) {
    if (pulses <= 0) {
      throw PodDoseException('Bolus must be at least one pulse');
    }
    if (pulses > maxPulses) {
      throw PodDoseException(
        'Bolus ${pulses * pulseUnits} U exceeds the pod maximum of $maxUnits U',
      );
    }
    return PodBolusAmount._(pulses);
  }

  /// One pod pulse, the smallest amount it can deliver.
  static const double pulseUnits = 0.05;
  static const int unitHundredthsPerPulse = 5;

  /// The pod's own single-bolus ceiling. This is a protocol limit, not a user
  /// preference — a user cap belongs on top of it, never instead of it.
  static const double maxUnits = 30.0;
  static const int maxPulses = 600;

  final int pulses;

  double get units => pulses * pulseUnits;

  @override
  String toString() => '${units.toStringAsFixed(2)} U ($pulses pulses)';
}

/// Programs an immediate bolus.
///
/// The frame carries the dose three times over: the pod's own interlock command
/// (0x1a) repeats the pulse count and an additive checksum of it, and the bolus
/// command (0x17) repeats it again in tenths of a pulse. All three are built
/// from one [PodBolusAmount], and [encoded] reads them back out of the finished
/// bytes and compares them before handing the frame over — so a mistake in this
/// encoder becomes a refusal rather than a wrong dose.
///
/// Extended (square-wave) boluses are deliberately not implemented: the trailing
/// fields stay zero.
class PodProgramBolusCommand extends PodCommand {
  PodProgramBolusCommand({
    required super.uniqueId,
    required super.sequenceNumber,
    required this.nonce,
    required this.amount,
    this.reminder = const PodProgramReminder(),
    this.eighthSecondsBetweenPulses = defaultEighthSecondsBetweenPulses,
    super.multiCommand,
  });

  /// Two seconds per pulse, the rate the pod delivers a normal bolus at.
  static const int defaultEighthSecondsBetweenPulses = 16;

  final int nonce;
  final PodBolusAmount amount;
  final PodProgramReminder reminder;
  final int eighthSecondsBetweenPulses;

  @override
  PodCommandType get type => PodCommandType.programBolus;

  int get _pulseSpacing => amount.pulses * eighthSecondsBetweenPulses;

  @override
  Uint8List get encoded {
    if (eighthSecondsBetweenPulses <= 0 || eighthSecondsBetweenPulses > 0xFF) {
      throw PodDoseException('Pulse spacing out of range');
    }
    if (_pulseSpacing > 0xFFFF || amount.pulses * 10 > 0xFFFF) {
      throw PodDoseException('Bolus too large to encode without overflow');
    }
    final frame = appendCrc(joinParts([
      buildHeader(_interlock.length + _bolusBody.length),
      _interlock,
      _bolusBody,
    ]));
    _verifyEncodedDose(frame);
    return frame;
  }

  /// The 0x1a interlock the pod requires immediately before a delivery command.
  PodInsulinInterlock get _interlockCommand => PodInsulinInterlock(
        nonce: nonce,
        deliveryType: PodInsulinDeliveryType.bolus,
        checksum: PodInsulinInterlock.bolusChecksum(
          pulses: amount.pulses,
          pulseSpacing: _pulseSpacing,
        ),
        byte9: 0x01,
        byte10And11: _pulseSpacing,
        byte12And13: amount.pulses,
        elements: [bigEndian16(amount.pulses)],
      );

  Uint8List get _interlock => _interlockCommand.encoded;

  Uint8List get _bolusBody => joinParts([
        [type.value, 13],
        reminder.encoded,
        bigEndian16(amount.pulses * 10),
        bigEndian32(eighthSecondsBetweenPulses ~/ 8 * 100000),
        [0x00, 0x00],
        [0x00, 0x00, 0x00, 0x00],
      ]);

  /// Reads the dose back out of the finished frame and refuses to release it
  /// unless every copy agrees with [amount]. This is the last gate before an
  /// encoding mistake would reach the pod as insulin.
  void _verifyEncodedDose(Uint8List frame) {
    final view = ByteData.view(frame.buffer, frame.offsetInBytes);
    final interlockStart = PodCommand.headerLength;
    final interlockPulses = view.getUint16(interlockStart + 12);
    final interlockElement = view.getUint16(interlockStart + 14);
    final bolusStart = interlockStart + _interlock.length;
    final tenthPulses = view.getUint16(bolusStart + 3);

    if (interlockPulses != amount.pulses ||
        interlockElement != amount.pulses ||
        tenthPulses != amount.pulses * 10) {
      throw PodDoseException(
        'Encoded bolus does not match the requested $amount — refusing to send',
      );
    }
    final trailerStart = frame.length - 2;
    if (view.getUint16(trailerStart) != PodCrc16(frame.sublist(0, trailerStart)).value) {
      throw PodDoseException('Bolus frame failed its own CRC check');
    }
  }
}
