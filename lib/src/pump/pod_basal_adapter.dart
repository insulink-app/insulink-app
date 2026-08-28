import 'package:insulink/src/profile/basal/basal_profile.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';

/// Turns the app's own basal profile into the schedule a pod can hold.
///
/// The two disagree only on resolution: the app edits one rate per HOUR, the pod
/// stores one per HALF hour. So each hour becomes two identical slots — no
/// interpolation, no smoothing. Inventing intermediate rates the user never
/// entered would deliver something other than what the profile shows.
///
/// Consecutive equal hours are left as separate slots on purpose; the pod's own
/// encoder groups equal runs into program elements, so grouping here as well
/// would only duplicate that.
class PodBasalAdapter {
  const PodBasalAdapter(this.profile);

  final BasalProfile profile;

  /// The pod's own limit on a basal rate.
  static const double maxRatePerHour = 30.0;

  /// Builds the pod schedule, or throws [PodBasalProgramException] if the profile
  /// cannot be represented.
  ///
  /// The pod meters basal in the same 0.05 U/h steps [BasalProfile.snap] already
  /// rounds to, so a profile edited in the app converts exactly. A rate that is
  /// somehow off that grid is refused rather than silently rounded — the schedule
  /// is what runs unattended for the pod's whole life.
  PodBasalProgram get program {
    if (profile.rates.length != _hoursPerDay) {
      throw PodBasalProgramException(
        'Basal profile must cover $_hoursPerDay hours, got ${profile.rates.length}',
      );
    }
    return PodBasalProgram([
      for (var hour = 0; hour < _hoursPerDay; hour++)
        _segmentFor(hour, profile.rates[hour]),
    ]);
  }

  PodBasalSegment _segmentFor(int hour, double ratePerHour) {
    if (ratePerHour.isNaN || ratePerHour.isInfinite || ratePerHour < 0) {
      throw PodBasalProgramException(
        'Basal rate for hour $hour is not usable: $ratePerHour',
      );
    }
    if (ratePerHour > maxRatePerHour) {
      throw PodBasalProgramException(
        'Basal rate ${ratePerHour}U/h at hour $hour is above the pod maximum '
        'of ${maxRatePerHour}U/h',
      );
    }
    final hundredths = (ratePerHour * 100).round();
    if ((hundredths / 100 - ratePerHour).abs() > 1e-9) {
      throw PodBasalProgramException(
        'Basal rate $ratePerHour U/h at hour $hour is finer than 0.01 U/h',
      );
    }
    if (hundredths % _hundredthsPerStep != 0) {
      throw PodBasalProgramException(
        'Basal rate $ratePerHour U/h at hour $hour is not a multiple of '
        '${BasalProfile.step} U/h',
      );
    }
    return PodBasalSegment(
      startSlot: hour * _slotsPerHour,
      endSlot: (hour + 1) * _slotsPerHour,
      rateHundredthUnitsPerHour: hundredths,
    );
  }

  /// Whether the profile can be programmed at all, without throwing — for a UI
  /// that wants to disable a button rather than catch.
  bool get isProgrammable {
    try {
      program;
      return true;
    } on PodBasalProgramException {
      return false;
    }
  }

  /// Why the profile cannot be programmed, or null when it can.
  String? get problem {
    try {
      program;
      return null;
    } on PodBasalProgramException catch (error) {
      return error.message;
    }
  }

  static const int _hoursPerDay = 24;
  static const int _slotsPerHour = 2;

  /// 0.05 U/h expressed in the hundredths the pod counts in.
  static const int _hundredthsPerStep = 5;
}
