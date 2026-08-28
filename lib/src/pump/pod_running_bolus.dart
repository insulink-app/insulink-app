import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';

/// A bolus the pod is working through right now.
///
/// The pod does not push a bolus out in one go: it delivers one 0.05 U pulse at a
/// time, two seconds apart by default, so a 4 U bolus takes about two and a half
/// minutes. Nothing on screen would say so without this.
///
/// Progress is computed from the CLOCK, not read from the pod. Reading it would
/// mean a BLE session every couple of seconds, which the pod's radio and the
/// sensor's scanner both would not survive. The rate is exact — the pod was told
/// it — so the estimate is off by at most the pulse it is mid-way through.
class PodRunningBolus {
  const PodRunningBolus({
    required this.startedAt,
    required this.pulses,
    required this.eighthSecondsBetweenPulses,
  });

  factory PodRunningBolus.fromJson(Map<String, dynamic> json) =>
      PodRunningBolus(
        startedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['started_at'] as num).toInt(),
        ),
        pulses: (json['pulses'] as num).toInt(),
        eighthSecondsBetweenPulses:
            (json['eighth_seconds_between_pulses'] as num).toInt(),
      );

  /// When the pod confirmed it had taken the bolus.
  final DateTime startedAt;

  /// Pulses programmed. One pulse is [PodBolusAmount.pulseUnits].
  final int pulses;

  /// The gap between pulses the pod was given, in eighths of a second.
  final int eighthSecondsBetweenPulses;

  Map<String, dynamic> toJson() => {
        'started_at': startedAt.millisecondsSinceEpoch,
        'pulses': pulses,
        'eighth_seconds_between_pulses': eighthSecondsBetweenPulses,
      };

  /// Total units this bolus was programmed for.
  double get programmedUnits => pulses * PodBolusAmount.pulseUnits;

  /// How long the whole bolus takes.
  Duration get duration => Duration(
        milliseconds: pulses * eighthSecondsBetweenPulses * 125,
      );

  /// Pulses the pod has finished, FLOORED.
  ///
  /// Floored on purpose rather than rounded: a pulse counts once it is out, and
  /// the honest direction to be wrong in is understating what the user has had.
  /// Overstating it would suppress a correction they actually need.
  int deliveredPulses(DateTime now) {
    final elapsed = now.difference(startedAt).inMilliseconds;
    if (elapsed <= 0) {
      return 0;
    }
    final perPulse = eighthSecondsBetweenPulses * 125;
    final done = elapsed ~/ perPulse;
    return done > pulses ? pulses : done;
  }

  double deliveredUnits(DateTime now) =>
      deliveredPulses(now) * PodBolusAmount.pulseUnits;

  /// How far along, from 0 to 1, for a progress bar.
  double progress(DateTime now) =>
      pulses == 0 ? 1 : deliveredPulses(now) / pulses;

  /// Whether the pod should have finished by now.
  ///
  /// The record is kept until this is true and then dropped; a bolus that has
  /// finished is history, and history belongs in the delivery log.
  bool isFinished(DateTime now) => !now.isBefore(startedAt.add(duration));

  Duration remaining(DateTime now) {
    final left = startedAt.add(duration).difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}
