import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_basal_elements.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_crc.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_insulin_interlock.dart';
import 'package:insulink/src/pump/protocol/pod_pulse_runs.dart';

/// A temporary basal rate and how long it runs for.
///
/// The pod only understands whole 30-minute slots, so a duration that is not a
/// multiple of 30 minutes is refused rather than rounded — a temp basal that
/// runs longer than the user asked for keeps delivering after they expect it to
/// stop.
class PodTempBasalRate {
  PodTempBasalRate._({required this.unitsPerHour, required this.slots});

  factory PodTempBasalRate({
    required double unitsPerHour,
    required int minutes,
  }) {
    if (unitsPerHour.isNaN || unitsPerHour.isInfinite || unitsPerHour < 0) {
      throw PodBasalProgramException(
        'Temp basal rate $unitsPerHour U/h is not usable',
      );
    }
    if (unitsPerHour > maxUnitsPerHour) {
      throw PodBasalProgramException(
        'Temp basal $unitsPerHour U/h is above the pod maximum of $maxUnitsPerHour U/h',
      );
    }
    if (minutes % minutesPerSlot != 0 || minutes <= 0) {
      throw PodBasalProgramException(
        'Temp basal duration must be a positive multiple of 30 minutes, got $minutes',
      );
    }
    final slots = minutes ~/ minutesPerSlot;
    if (slots > maxSlots) {
      throw PodBasalProgramException(
        'Temp basal duration $minutes min is above the maximum of ${maxSlots * minutesPerSlot} min',
      );
    }
    return PodTempBasalRate._(unitsPerHour: unitsPerHour, slots: slots);
  }

  /// The pod's own temp-basal rate ceiling.
  static const double maxUnitsPerHour = 30.0;

  /// The pod's basal slot length; a temp basal is a whole number of these.
  static const int minutesPerSlot = 30;

  /// Twelve hours, the longest temp basal the pod accepts.
  static const int maxSlots = 24;

  final double unitsPerHour;
  final int slots;

  int get minutes => slots * minutesPerSlot;

  int get pulsesPerHour => (unitsPerHour * 20).round();

  /// Whole pulses per slot, alternating the odd pulse the way the pod does.
  List<int> get pulsesPerSlot {
    final out = List<int>.filled(slots, 0);
    var oweExtraPulse = false;
    for (var slot = 0; slot < slots; slot++) {
      out[slot] = pulsesPerHour ~/ 2;
      if (pulsesPerHour.isOdd) {
        if (oweExtraPulse) {
          out[slot] += 1;
        }
        oweExtraPulse = !oweExtraPulse;
      }
    }
    return out;
  }

  /// Whether this rate is delivered as a token trickle instead of nothing.
  ///
  /// The pod cancels a genuine zero-rate temp basal that runs longer than four
  /// slots, so a 0 U/h request beyond two hours is programmed as one tenth of a
  /// pulse per slot — about 0.01 U/h — to keep it alive. That is not what the
  /// user asked for, so the UI has to say so rather than show "0 U/h".
  bool get isTrickleSubstituted => pulsesPerHour == 0 && slots > 4;

  List<int> get tenthPulsesPerSlot {
    final perSlot = isTrickleSubstituted ? 1 : pulsesPerHour * 5;
    return List<int>.filled(slots, perSlot);
  }
}

/// Programs a temporary basal rate, overriding the schedule for a set time.
class PodProgramTempBasalCommand extends PodCommand {
  PodProgramTempBasalCommand({
    required super.uniqueId,
    required super.sequenceNumber,
    required this.nonce,
    required this.rate,
    this.reminder = const PodProgramReminder(),
    super.multiCommand,
  });

  final int nonce;
  final PodTempBasalRate rate;
  final PodProgramReminder reminder;

  /// The fixed value the interlock carries where a full-day program would put
  /// the eighth-seconds remaining in the current slot: 0x3840 is one whole slot,
  /// because a temp basal always starts at the beginning of its first slot.
  static const int _wholeSlotEighthSeconds = 0x3840;

  @override
  PodCommandType get type => PodCommandType.programTempBasal;

  List<PodBasalLongElement> get _longElements {
    final perSlot = rate.tenthPulsesPerSlot;
    final elements = <PodBasalLongElement>[];
    var runLength = 0;
    for (var slot = 0; slot < perSlot.length; slot++) {
      final wouldOverflow = (runLength + 1) * perSlot[slot] > 65534;
      if (runLength > 0 && wouldOverflow) {
        elements.add(
          PodBasalLongElement(
            slotCount: runLength,
            totalTenthPulses: perSlot[slot] * runLength,
          ),
        );
        runLength = 0;
      }
      runLength++;
    }
    elements.add(
      PodBasalLongElement(
        slotCount: runLength,
        totalTenthPulses: perSlot.first * runLength,
      ),
    );
    return elements;
  }

  List<PodBasalShortElement> get _shortElements =>
      PodPulseRuns(rate.pulsesPerSlot).elements;

  @override
  Uint8List get encoded {
    final interlock = _interlock.encoded;
    final body = _tempBasalBody;
    return appendCrc(
      joinParts([buildHeader(interlock.length + body.length), interlock, body]),
    );
  }

  PodInsulinInterlock get _interlock {
    final perSlot = rate.pulsesPerSlot;
    return PodInsulinInterlock(
      nonce: nonce,
      deliveryType: PodInsulinDeliveryType.tempBasal,
      checksum: PodAdditiveChecksum(<int>[
        rate.slots & 0xFF,
        (_wholeSlotEighthSeconds >> 8) & 0xFF,
        _wholeSlotEighthSeconds & 0xFF,
        (perSlot.first >> 8) & 0xFF,
        perSlot.first & 0xFF,
        for (final pulses in perSlot) ...[(pulses >> 8) & 0xFF, pulses & 0xFF],
      ]).value,
      byte9: rate.slots,
      byte10And11: _wholeSlotEighthSeconds,
      byte12And13: perSlot.first,
      elements: [for (final element in _shortElements) element.encoded],
    );
  }

  Uint8List get _tempBasalBody {
    final elements = _longElements;
    final first = elements.first;
    final remaining = first.isZeroRate
        ? first.slotCount
        : first.totalTenthPulses;
    final delay = first.isZeroRate
        ? PodBasalProgram.maxDelayBetweenTenthPulsesUsec
        : (first.slotCount * 1800.0 / remaining * 1000000).toInt();
    return joinParts([
      [type.value, elements.length * 6 + 8],
      reminder.encoded,
      [0x00],
      bigEndian16(remaining),
      bigEndian32(delay),
      for (final element in elements) element.encoded,
    ]);
  }
}
