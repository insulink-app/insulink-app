import 'dart:math' as math;

import 'package:insulink/src/pump/loop/loop_glucose.dart';
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
  const SplitBolusPlan({
    required this.parts,
    required this.mealKey,
    this.sendingSince,
  });

  /// Spreads [pulses] evenly over [over], one part every [partEvery] from
  /// [from]; parts that would carry no pulse are left out.
  factory SplitBolusPlan.spread(
    int pulses, {
    required Duration over,
    required DateTime from,
    required int mealKey,
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
    return SplitBolusPlan(parts: parts, mealKey: mealKey);
  }

  factory SplitBolusPlan.fromJson(Map<String, dynamic> json) => SplitBolusPlan(
    parts: [
      for (final part in json['parts'] as List<dynamic>)
        SplitBolusPart.fromJson(part as Map<String, dynamic>),
    ],
    mealKey: json['meal_key'] as int,
    sendingSince: switch (json['sending_since']) {
      final int millis => DateTime.fromMillisecondsSinceEpoch(millis),
      _ => null,
    },
  );

  /// The gap between two parts.
  static const partEvery = Duration(minutes: 15);

  /// A part this far past its time is not given any more: the service was not
  /// running, and insulin for a drink an hour ago is not what the user asked for.
  static const lateAfter = Duration(minutes: 15);

  final List<SplitBolusPart> parts;

  /// The [Meal.logKey] of the meal this bolus was confirmed for. Each part is
  /// logged with it as `splitOf`, so the automation counts the parts and the
  /// planned rest as covering that meal's carbs rather than as a correction.
  final int mealKey;

  /// Set while the first part is on its way to the pod. Found set by a fresh
  /// process, it means the one before died mid-send: that part may have gone
  /// in and is never sent again. Also tells the sender whether the plan it
  /// finds afterwards is still its own.
  final DateTime? sendingSince;

  /// Units still to come at [now]. A part past [lateAfter] is never given, so
  /// it stops counting: a plan the service could not work off (no service
  /// running) must not hold back every correction for good.
  double remainingUnitsAt(DateTime now) => parts
      .where((part) => !now.isAfter(part.at.add(lateAfter)))
      .fold(0.0, (sum, part) => sum + part.units);

  /// Whether the first part has missed its time for good.
  bool missedAt(DateTime now) => now.isAfter(parts.first.at.add(lateAfter));

  /// This plan with its first part marked as being sent at [at].
  SplitBolusPlan sendingAt(DateTime at) => _copy(parts, sendingSince: at);

  /// Whether this plan carries the send mark [mark]. Compared in milliseconds,
  /// because that is all the stored copy keeps: [DateTime.now] carries
  /// microseconds, so the mark read back would never equal the one written.
  bool markedAt(DateTime mark) =>
      sendingSince?.millisecondsSinceEpoch == mark.millisecondsSinceEpoch;

  /// This plan with the send mark taken off, the first part still to come.
  SplitBolusPlan get settled => _copy(parts);

  SplitBolusPlan _copy(List<SplitBolusPart> parts, {DateTime? sendingSince}) =>
      SplitBolusPlan(
        parts: parts,
        mealKey: mealKey,
        sendingSince: sendingSince,
      );

  DateTime get endsAt => parts.last.at;

  /// The plan once its first part is given, or null when that was the last.
  SplitBolusPlan? get afterFirst =>
      parts.length <= 1 ? null : _copy(parts.sublist(1));

  Map<String, dynamic> toJson() => {
    'parts': [for (final part in parts) part.toJson()],
    'meal_key': mealKey,
    'sending_since': ?sendingSince?.millisecondsSinceEpoch,
  };
}

/// Stops a split bolus whose rest would land on a low: the glucose is at the
/// user's low line already, or its trend reaches it within [lookahead]. The
/// automation lowers the basal then, but the planned parts are boluses and
/// would keep coming regardless.
///
/// Without usable sensor data the part still goes, exactly as a pump's own
/// extended bolus would: the user asked for it, and the guard only exists to
/// overrule that request with evidence.
class SplitBolusLowGuard {
  const SplitBolusLowGuard(this.lowMgdl);

  static const lookahead = Duration(minutes: 30);

  final int lowMgdl;

  bool stops(LoopGlucose glucose) {
    if (!glucose.isUsable) {
      return false;
    }
    final ahead = glucose.mgdl + glucose.trendPerMinute * lookahead.inMinutes;
    return glucose.mgdl <= lowMgdl || ahead <= lowMgdl;
  }
}
