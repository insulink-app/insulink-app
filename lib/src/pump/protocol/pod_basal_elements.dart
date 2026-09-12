import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';
import 'package:insulink/src/pump/protocol/pod_pulse_runs.dart';

/// One stretch of equal-rate slots in the compact form the interlock carries:
/// a slot count, the pulses each slot gets, and whether the segment alternates
/// an extra pulse between slots.
class PodBasalShortElement {
  const PodBasalShortElement({
    required this.slotCount,
    required this.pulsesPerSlot,
    required this.extraAlternatePulse,
  });

  final int slotCount;
  final int pulsesPerSlot;
  final bool extraAlternatePulse;

  Uint8List get encoded => Uint8List.fromList([
    (((slotCount - 1) & 0x0f) << 4) |
        ((extraAlternatePulse ? 1 : 0) << 3) |
        ((pulsesPerSlot >> 8) & 0x03),
    pulsesPerSlot & 0xFF,
  ]);
}

/// One stretch of equal-rate slots in the form the basal command carries: the
/// total tenths of a pulse over the stretch, and the microsecond spacing
/// between them.
///
/// A stretch that delivers nothing cannot state a spacing, so the pod encodes
/// it differently: the first field carries the SLOT COUNT instead of the (zero)
/// pulse total, the spacing is one slot, and the top bit of the spacing marks
/// the stretch as zero-rate. Writing a plain zero there produces a frame the
/// pod does not accept.
class PodBasalLongElement {
  const PodBasalLongElement({
    required this.slotCount,
    required this.totalTenthPulses,
  });

  static const int _zeroRateFlag = 0x80000000;

  final int slotCount;
  final int totalTenthPulses;

  bool get isZeroRate => totalTenthPulses == 0;

  /// The spacing between tenth-pulses. For a zero-rate stretch this is the
  /// one-slot placeholder the pod expects rather than a real rate.
  ///
  /// The reference implementation computes the placeholder as
  /// `durationInSeconds * 1000000 / slotCount` through a 16-bit intermediate,
  /// which is exactly one slot for every stretch up to 18 slots and overflows
  /// into a negative number beyond that. The value is algebraically independent
  /// of the slot count, so it is written directly here — identical to the
  /// reference wherever the reference does not overflow.
  int get delayBetweenTenthPulsesUsec {
    if (isZeroRate) {
      return PodBasalProgram.maxDelayBetweenTenthPulsesUsec;
    }
    return PodBasalProgram.maxDelayBetweenTenthPulsesUsec *
        slotCount ~/
        totalTenthPulses;
  }

  Uint8List get encoded {
    final out = Uint8List(6);
    final view = ByteData.view(out.buffer);
    view.setUint16(0, (isZeroRate ? slotCount : totalTenthPulses) & 0xFFFF);
    final delay = isZeroRate
        ? _zeroRateFlag | delayBetweenTenthPulsesUsec
        : delayBetweenTenthPulsesUsec;
    view.setUint32(2, delay & 0xFFFFFFFF);
    return out;
  }
}

/// Where the pod is inside the long element that is running now.
class PodCurrentLongElement {
  const PodCurrentLongElement({
    required this.index,
    required this.delayUntilNextTenthPulseUsec,
    required this.remainingTenthPulses,
  });

  final int index;
  final int delayUntilNextTenthPulseUsec;
  final int remainingTenthPulses;
}

/// Turns a basal schedule into the two element lists a program command needs.
///
/// Both lists describe the same day at different resolutions and the pod checks
/// them against each other, so they are derived here from one program rather
/// than assembled separately at the call sites.
class PodBasalElements {
  PodBasalElements(this.program);

  static const int _maxTenthPulsesPerElement = 65534;

  final PodBasalProgram program;

  /// Runs of equal tenth-pulse counts, split where a run would overflow the
  /// 16-bit total.
  List<PodBasalLongElement> get longElements {
    final perSlot = program.tenthPulsesPerSlot;
    final elements = <PodBasalLongElement>[];
    var previous = 0;
    var slotsInElement = 0;
    for (var slot = 0; slot < perSlot.length; slot++) {
      if (slot == 0) {
        previous = perSlot[slot];
        slotsInElement = 1;
        continue;
      }
      final wouldOverflow =
          (slotsInElement + 1) * previous > _maxTenthPulsesPerElement;
      if (previous != perSlot[slot] || wouldOverflow) {
        elements.add(
          PodBasalLongElement(
            slotCount: slotsInElement,
            totalTenthPulses: previous * slotsInElement,
          ),
        );
        previous = perSlot[slot];
        slotsInElement = 1;
        continue;
      }
      slotsInElement++;
    }
    elements.add(
      PodBasalLongElement(
        slotCount: slotsInElement,
        totalTenthPulses: previous * slotsInElement,
      ),
    );
    return elements;
  }

  /// Runs of equal whole-pulse counts, as the interlock carries them.
  List<PodBasalShortElement> get shortElements =>
      PodPulseRuns(program.pulsesPerSlot).elements;

  /// Which long element covers [time], and how much of it is left.
  PodCurrentLongElement currentLongElementAt(DateTime time) {
    final secondOfDay = time.hour * 3600 + time.minute * 60 + time.second;
    var startSlot = 0;
    var index = 0;
    for (final element in longElements) {
      final startSecond = startSlot * PodBasalProgram.secondsPerSlot;
      final endSecond =
          startSecond + element.slotCount * PodBasalProgram.secondsPerSlot;
      if (secondOfDay >= startSecond && secondOfDay < endSecond) {
        return _resolve(element, index, startSecond, endSecond, secondOfDay);
      }
      index++;
      startSlot += element.slotCount;
    }
    throw PodBasalProgramException(
      'No basal element covers second $secondOfDay',
    );
  }

  PodCurrentLongElement _resolve(
    PodBasalLongElement element,
    int index,
    int startSecond,
    int endSecond,
    int secondOfDay,
  ) {
    var totalTenThousandths = element.totalTenthPulses * 1000;
    if (totalTenThousandths == 0) {
      totalTenThousandths = element.slotCount * 1000;
    }
    final duration = endSecond - startSecond;
    final elapsed = secondOfDay - startSecond;
    final remainingTenThousandths =
        ((duration - elapsed) / duration * totalTenThousandths).toInt();
    final spacing = duration * 1000000 * 1000 ~/ totalTenThousandths;

    var delayUntilNext = spacing;
    final secondsIntoSlot = elapsed % PodBasalProgram.secondsPerSlot;
    for (var step = 0; step < secondsIntoSlot; step++) {
      delayUntilNext -= 1000000;
      while (delayUntilNext <= 0) {
        delayUntilNext += spacing;
      }
    }
    return PodCurrentLongElement(
      index: index,
      delayUntilNextTenthPulseUsec: delayUntilNext,
      remainingTenthPulses:
          (remainingTenThousandths % 1000 != 0 ? 1 : 0) +
          remainingTenThousandths ~/ 1000,
    );
  }
}
