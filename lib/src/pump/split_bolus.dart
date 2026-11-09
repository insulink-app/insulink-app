import 'dart:math' as math;

import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';

/// One later piece of a split bolus, in whole pod pulses so it is deliverable
/// exactly as planned.
class SplitBolusPart {
  const SplitBolusPart({required this.at, required this.pulses});

  factory SplitBolusPart.fromJson(Map<String, dynamic> json) => SplitBolusPart(
    at: DateTime.fromMillisecondsSinceEpoch(json['at'] as int),
    pulses: json['pulses'] as int,
  );

  final DateTime at;
  final int pulses;

  double get units => pulses * PodBolusAmount.pulseUnits;

  Map<String, dynamic> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'pulses': pulses,
  };
}

/// The rest of a bolus the user chose to spread out, for a drink or a meal
/// that is absorbed slowly: the pod's own extended bolus is not implemented
/// (`PodProgramBolusCommand`), so the rest goes out as ordinary boluses every
/// [partEvery], given by the service isolate so it continues with the app
/// closed.
///
/// Counted as insulin on board in full until it is given. That overstates what
/// is acting now, which is the safe side for every reader: the calculator and
/// the automation both hold back rather than stack insulin on a dose that is
/// already promised.
class SplitBolusPlan {
  const SplitBolusPlan({required this.parts, required this.glucoseMgdl});

  /// Spreads [pulses] evenly over [over], one part every [partEvery] from
  /// [from]; parts that would carry no pulse are left out.
  factory SplitBolusPlan.spread(
    int pulses, {
    required Duration over,
    required DateTime from,
    required int glucoseMgdl,
  }) {
    final count = math.max(1, over.inMinutes ~/ partEvery.inMinutes);
    final parts = <SplitBolusPart>[];
    for (var index = 0; index < count; index++) {
      final share = pulses * (index + 1) ~/ count - pulses * index ~/ count;
      if (share > 0) {
        parts.add(
          SplitBolusPart(at: from.add(partEvery * (index + 1)), pulses: share),
        );
      }
    }
    return SplitBolusPlan(parts: parts, glucoseMgdl: glucoseMgdl);
  }

  factory SplitBolusPlan.fromJson(Map<String, dynamic> json) => SplitBolusPlan(
    parts: [
      for (final part in json['parts'] as List<dynamic>)
        SplitBolusPart.fromJson(part as Map<String, dynamic>),
    ],
    glucoseMgdl: json['glucose_mgdl'] as int,
  );

  /// The gap between two parts.
  static const partEvery = Duration(minutes: 15);

  /// A part this far past its time is not given any more: the service was not
  /// running, and insulin for a drink an hour ago is not what the user asked for.
  static const lateAfter = Duration(minutes: 15);

  final List<SplitBolusPart> parts;

  /// Glucose when the bolus was confirmed, written onto each part's log entry.
  final int glucoseMgdl;

  double get remainingUnits => parts.fold(0.0, (sum, part) => sum + part.units);

  DateTime get endsAt => parts.last.at;

  /// The plan once its first part is given, or null when that was the last.
  SplitBolusPlan? get afterFirst => parts.length <= 1
      ? null
      : SplitBolusPlan(parts: parts.sublist(1), glucoseMgdl: glucoseMgdl);

  Map<String, dynamic> toJson() => {
    'parts': [for (final part in parts) part.toJson()],
    'glucose_mgdl': glucoseMgdl,
  };
}
