import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';

/// Raised when a basal schedule cannot be represented on the pod.
class PodBasalProgramException implements Exception {
  PodBasalProgramException(this.message);

  final String message;

  @override
  String toString() => 'PodBasalProgramException: $message';
}

/// One stretch of the day at a constant rate, measured in the pod's 30-minute
/// slots: [startSlot] inclusive, [endSlot] exclusive, of 48 slots per day.
class PodBasalSegment {
  const PodBasalSegment({
    required this.startSlot,
    required this.endSlot,
    required this.rateHundredthUnitsPerHour,
  });

  /// Builds a segment from wall-clock half-hours and a rate in U/h.
  factory PodBasalSegment.fromHours({
    required double startHour,
    required double endHour,
    required double unitsPerHour,
  }) {
    final start = (startHour * 2).round();
    final end = (endHour * 2).round();
    final hundredths = (unitsPerHour * 100).round();
    if ((hundredths / 100 - unitsPerHour).abs() > 1e-9) {
      throw PodBasalProgramException(
        'Rate $unitsPerHour U/h is finer than 0.01 U/h',
      );
    }
    return PodBasalSegment(
      startSlot: start,
      endSlot: end,
      rateHundredthUnitsPerHour: hundredths,
    );
  }

  final int startSlot;
  final int endSlot;
  final int rateHundredthUnitsPerHour;

  int get slotCount => endSlot - startSlot;

  /// Pulses the pod delivers per hour at this rate, at 20 pulses per unit.
  int get pulsesPerHour => rateHundredthUnitsPerHour * 20 ~/ 100;

  double get unitsPerHour => rateHundredthUnitsPerHour / 100;
}

/// Where the pod is inside the current 30-minute basal slot.
class PodCurrentSlot {
  const PodCurrentSlot({
    required this.index,
    required this.eighthSecondsRemaining,
    required this.pulsesRemaining,
  });

  final int index;
  final int eighthSecondsRemaining;
  final int pulsesRemaining;
}

/// A full-day basal schedule, as the pod stores it: 48 half-hour slots that
/// must be covered exactly once, with no gap and no overlap.
///
/// The pod meters in whole pulses per slot, so a rate whose hourly pulse count
/// is odd cannot be split evenly across two half-hours. The pod's answer is to
/// alternate — one slot gets the extra pulse, the next does not — and both slot
/// maps below reproduce that, because the schedule and its checksum have to
/// agree on which slot got it.
class PodBasalProgram {
  PodBasalProgram(this.segments) {
    _validate();
  }

  static const int slotsPerDay = 48;
  static const int secondsPerSlot = 1800;

  /// The reference delay the pod scales its per-slot pulse spacing from.
  static const int maxDelayBetweenTenthPulsesUsec = 1800000000;

  final List<PodBasalSegment> segments;

  void _validate() {
    if (segments.isEmpty) {
      throw PodBasalProgramException('Basal program has no segments');
    }
    var expectedStart = 0;
    for (final segment in segments) {
      if (segment.startSlot != expectedStart) {
        throw PodBasalProgramException(
          'Segment starts at slot ${segment.startSlot}, expected $expectedStart',
        );
      }
      if (segment.endSlot <= segment.startSlot) {
        throw PodBasalProgramException('Segment ends before it starts');
      }
      if (segment.rateHundredthUnitsPerHour < 0) {
        throw PodBasalProgramException('Negative basal rate');
      }
      expectedStart = segment.endSlot;
    }
    if (expectedStart != slotsPerDay) {
      throw PodBasalProgramException(
        'Basal program covers $expectedStart of $slotsPerDay slots',
      );
    }
  }

  double get totalDailyUnits => segments.fold<double>(
    0,
    (sum, segment) => sum + segment.unitsPerHour * segment.slotCount / 2,
  );

  /// Whole pulses per slot, alternating the odd pulse within each segment.
  List<int> get pulsesPerSlot {
    final slots = List<int>.filled(slotsPerDay, 0);
    for (final segment in segments) {
      var oweExtraPulse = false;
      for (var slot = segment.startSlot; slot < segment.endSlot; slot++) {
        slots[slot] = segment.pulsesPerHour ~/ 2;
        if (segment.pulsesPerHour.isOdd) {
          if (oweExtraPulse) {
            slots[slot] += 1;
          }
          oweExtraPulse = !oweExtraPulse;
        }
      }
    }
    return slots;
  }

  /// Tenths of a pulse per slot — the finer scale the long program elements
  /// use, where the odd pulse needs no alternating because half a pulse is
  /// representable.
  List<int> get tenthPulsesPerSlot {
    final slots = List<int>.filled(slotsPerDay, 0);
    for (final segment in segments) {
      for (var slot = segment.startSlot; slot < segment.endSlot; slot++) {
        slots[slot] = segment.pulsesPerHour * 5;
      }
    }
    return slots;
  }

  /// The rate running at [time], in U/h.
  double rateAt(DateTime time) {
    final slot = time.hour * 2 + time.minute ~/ 30;
    for (final segment in segments) {
      if (slot >= segment.startSlot && slot < segment.endSlot) {
        return segment.unitsPerHour;
      }
    }
    return 0;
  }

  /// How far into the current slot [time] is, and what is left to deliver in it.
  PodCurrentSlot currentSlotAt(DateTime time) {
    final index = (time.hour * 60 + time.minute) ~/ 30;
    final secondOfDay = time.hour * 3600 + time.minute * 60 + time.second;
    final secondsRemaining = (index + 1) * secondsPerSlot - secondOfDay;
    final pulses = pulsesPerSlot[index];
    return PodCurrentSlot(
      index: index,
      eighthSecondsRemaining: secondsRemaining * 8,
      pulsesRemaining: (pulses * secondsRemaining / secondsPerSlot).toInt(),
    );
  }

  /// Whether any slot delivers nothing. A zero-rate segment is legal on the pod
  /// but means basal genuinely stops there, so callers that did not intend it
  /// should ask the user rather than program it silently.
  bool get hasZeroSegments =>
      segments.any((segment) => segment.rateHundredthUnitsPerHour == 0);

  /// The daily total expressed in pod pulses, for cross-checking against a
  /// reservoir before programming.
  int get totalDailyPulses =>
      (totalDailyUnits / PodBolusAmount.pulseUnits).round();
}
