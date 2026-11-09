import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/split_bolus.dart';

/// What the injection page's split-bolus controls are set to, and how a dose
/// divides under it. Off, the dose goes out whole, exactly as before.
class SplitBolusChoice {
  const SplitBolusChoice({
    this.enabled = false,
    this.nowPercent = 50,
    this.overMinutes = 60,
  });

  static const nowPercents = [0, 25, 50, 75];
  static const overMinuteOptions = [30, 60, 90, 120];

  final bool enabled;

  /// Share of the dose given at once.
  final int nowPercent;

  /// Time the rest is spread over.
  final int overMinutes;

  SplitBolusChoice copyWith({
    bool? enabled,
    int? nowPercent,
    int? overMinutes,
  }) => SplitBolusChoice(
    enabled: enabled ?? this.enabled,
    nowPercent: nowPercent ?? this.nowPercent,
    overMinutes: overMinutes ?? this.overMinutes,
  );

  /// [units] on the pod's pulse grid, counted in pulses.
  int _pulses(double units) =>
      (PodBolusAmount.snapToPulse(units) * 100).round() ~/
      PodBolusAmount.unitHundredthsPerPulse;

  int _nowPulses(double units) => _pulses(units) * nowPercent ~/ 100;

  /// What goes out at once: all of [units] while the split is off.
  double nowUnits(double units) =>
      enabled ? _nowPulses(units) * PodBolusAmount.pulseUnits : units;

  /// What is spread out later, zero while the split is off.
  double laterUnits(double units) => enabled
      ? (_pulses(units) - _nowPulses(units)) * PodBolusAmount.pulseUnits
      : 0;

  /// The later parts of [units] from [from], or null when nothing is left for
  /// later.
  SplitBolusPlan? plan(
    double units, {
    required DateTime from,
    required int glucoseMgdl,
  }) {
    final later = _pulses(units) - _nowPulses(units);
    if (!enabled || later <= 0) {
      return null;
    }
    return SplitBolusPlan.spread(
      later,
      over: Duration(minutes: overMinutes),
      from: from,
      glucoseMgdl: glucoseMgdl,
    );
  }
}
