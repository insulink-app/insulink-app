part of '../pod_store.dart';

/// Whether the automation is delivering.
///
/// Two positions, not three. An earlier version had a middle "observing" setting
/// that computed without delivering, which turned out to be what OFF should
/// always have meant: the question a user asks about an automation they have not
/// switched on is what it WOULD have done, and answering it costs nothing.
enum PodLoopMode {
  /// The pod runs the user's basal schedule. Cycles are still computed and
  /// written to the journal, so the automation can be watched against a real day
  /// before it is trusted, but nothing is ever programmed.
  ///
  /// Those cycles cost no radio: they are decided from the status the background
  /// watch already read, not from a session opened to ask again.
  off,

  /// Cycles are computed and programmed onto the pod.
  engaged,
}

/// Why the automation stopped on its own. Recorded so the user is told what
/// happened rather than finding the mode quietly switched off.
///
/// A missing pod is deliberately not a cause: the automation waits for the next
/// pod instead (see [PodStore.forgetPod]).
enum PodLoopStop { podUnreachable, podNotDelivering, limitsInvalid }

/// One automated cycle, kept so an automated delivery can be reconstructed.
///
/// Stores the RATE above schedule rather than the units it committed to. What a
/// cycle actually delivered is its rate multiplied by how long it ran before the
/// next cycle replaced it, which is only known once that next cycle exists. A
/// stored unit count would have to claim the full fuse and would overstate every
/// cycle roughly sixfold.
class PodLoopCycle {
  const PodLoopCycle({
    required this.at,
    required this.unitsPerHour,
    required this.scheduledUnitsPerHour,
    required this.reason,
    required this.delivered,
    this.boundBy,
    this.mgdl,
    this.trendPerMinute,
    this.iobUnits = 0,
  });

  factory PodLoopCycle.fromJson(Map<String, dynamic> json) => PodLoopCycle(
    at: DateTime.fromMillisecondsSinceEpoch((json['at'] as num).toInt()),
    unitsPerHour: (json['rate'] as num).toDouble(),
    scheduledUnitsPerHour: (json['schedule'] as num).toDouble(),
    reason: LoopReason.values.firstWhere(
      (entry) => entry.name == json['reason'],
      orElse: () => LoopReason.noGlucose,
    ),
    delivered: json['sent'] == true,
    boundBy: LoopBound.values
        .where((entry) => entry.name == json['bound'])
        .firstOrNull,
    mgdl: (json['mgdl'] as num?)?.toInt(),
    trendPerMinute: (json['trend'] as num?)?.toDouble(),
    iobUnits: (json['iob'] as num?)?.toDouble() ?? 0,
  );

  final DateTime at;
  final double unitsPerHour;
  final double scheduledUnitsPerHour;
  final LoopReason reason;

  /// Whether this rate reached the pod. False in observation mode, and false for
  /// a cycle whose command failed, so the journal never claims insulin that was
  /// not programmed.
  final bool delivered;

  final LoopBound? boundBy;
  final int? mgdl;
  final double? trendPerMinute;
  final double iobUnits;

  Map<String, dynamic> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'rate': unitsPerHour,
    'schedule': scheduledUnitsPerHour,
    'reason': reason.name,
    'sent': delivered,
    if (boundBy != null) 'bound': boundBy!.name,
    if (mgdl != null) 'mgdl': mgdl,
    if (trendPerMinute != null) 'trend': trendPerMinute,
    'iob': iobUnits,
  };

  /// Insulin per hour this cycle added ON TOP of the user's schedule.
  ///
  /// Never negative. A rate below schedule withholds background insulin, which
  /// is not the same as removing insulin from the body, and letting it count as
  /// negative insulin on board would enlarge the next cycle's allowance on the
  /// strength of a dose that was never given.
  double get excessUnitsPerHour {
    final excess = unitsPerHour - scheduledUnitsPerHour;
    return delivered && excess > 0 ? excess : 0;
  }
}

/// The record of what the automation did, and the switch that turns it on.
///
/// Part of [PodStore] because it is pod state: it dies with the pod it describes,
/// and it is read by the background service through the same cache as everything
/// else the pod watch needs.
extension PodLoopJournal on PodStore {
  /// Cycles kept. One every five minutes fills this in about a day, which is the
  /// span worth being able to reconstruct.
  static const int maxCycles = 288;

  PodLoopMode get loopMode => PodLoopMode.values.firstWhere(
    (entry) => entry.name == _cache[PodStore._kLoopMode],
    orElse: () => PodLoopMode.off,
  );

  /// Switching it ON also starts the automation record, so the basal analysis
  /// knows from which moment an hour without an entry is an hour the automation
  /// stayed out of. Hours before the first time it was ever engaged need no
  /// clearing: nothing could have been running.
  Future<void> saveLoopMode(PodLoopMode mode) async {
    if (mode != PodLoopMode.off) {
      await startAutomationRecord();
    }
    await _set(PodStore._kLoopMode, mode.name);
  }

  /// Why the automation stopped by itself, or null when the user stopped it or
  /// it is still running.
  PodLoopStop? get loopStop => PodLoopStop.values
      .where((entry) => entry.name == _cache[PodStore._kLoopStop])
      .firstOrNull;

  /// Switches back to the basal schedule and records the cause.
  ///
  /// The mode is written BEFORE anything else acts on it, so a process that dies
  /// here restarts with the automation already off. Reverting the pod is a
  /// separate step that may fail; this one may not.
  Future<void> stopLoop(PodLoopStop cause) async {
    await _set(PodStore._kLoopStop, cause.name);
    await saveLoopMode(PodLoopMode.off);
  }

  Future<void> clearLoopStop() => _remove(PodStore._kLoopStop);

  /// Every recorded cycle, newest first.
  List<PodLoopCycle> get loopCycles {
    final encoded = _cache[PodStore._kLoopCycles];
    if (encoded == null || encoded.isEmpty) {
      return const [];
    }
    try {
      return [
        for (final entry in jsonDecode(encoded) as List<dynamic>)
          PodLoopCycle.fromJson(entry as Map<String, dynamic>),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> recordLoopCycle(PodLoopCycle cycle) async {
    final entries = [cycle, ...loopCycles];
    final kept = entries.length > maxCycles
        ? entries.sublist(0, maxCycles)
        : entries;
    await _set(
      PodStore._kLoopCycles,
      jsonEncode([for (final entry in kept) entry.toJson()]),
    );
  }

  /// Insulin the automation added above the schedule inside [window].
  ///
  /// Each cycle ran until the next one replaced it, so its share is its excess
  /// rate over that stretch. The newest cycle is still running and is counted up
  /// to [now].
  double automatedUnitsWithin(Duration window, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final since = at.subtract(window);
    return _excessUnits(from: since, to: at);
  }

  /// The automation's own contribution to insulin on board, decaying linearly
  /// over [insulinDuration] exactly as [ActiveInsulin] decays a bolus.
  ///
  /// Without this the loop would not see its own insulin. Its excess is real
  /// insulin in the body, so leaving it out would let each cycle add on top of
  /// the last, which is the way an automated system stacks a dose nobody chose.
  double loopIobUnits(Duration insulinDuration, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final cycles = loopCycles;
    var units = 0.0;
    for (var index = 0; index < cycles.length; index++) {
      final ranFrom = cycles[index].at;
      final ranTo = index == 0 ? at : cycles[index - 1].at;
      units += _remainingOf(cycles[index], ranFrom, ranTo, at, insulinDuration);
    }
    return units;
  }

  /// What is left of one cycle's excess, treating it as delivered evenly across
  /// the stretch it ran and decaying from the middle of that stretch.
  double _remainingOf(
    PodLoopCycle cycle,
    DateTime ranFrom,
    DateTime ranTo,
    DateTime at,
    Duration insulinDuration,
  ) {
    final window = _windowOf(cycle, ranFrom, ranTo, at);
    if (window == null) {
      return 0;
    }
    final delivered =
        cycle.excessUnitsPerHour *
        window.end.difference(window.start).inSeconds /
        Duration.secondsPerHour;
    if (delivered <= 0) {
      return 0;
    }
    final middle = window.start.add(window.end.difference(window.start) ~/ 2);
    final fraction =
        1 - at.difference(middle).inSeconds / insulinDuration.inSeconds;
    return delivered * fraction.clamp(0.0, 1.0);
  }

  double _excessUnits({required DateTime from, required DateTime to}) {
    final cycles = loopCycles;
    var units = 0.0;
    for (var index = 0; index < cycles.length; index++) {
      final ranFrom = cycles[index].at;
      final ranTo = index == 0 ? to : cycles[index - 1].at;
      final clippedFrom = ranFrom.isAfter(from) ? ranFrom : from;
      units += _unitsOver(cycles[index], clippedFrom, ranTo, to);
    }
    return units;
  }

  double _unitsOver(
    PodLoopCycle cycle,
    DateTime from,
    DateTime to,
    DateTime now,
  ) {
    final window = _windowOf(cycle, from, to, now);
    if (window == null) {
      return 0;
    }
    final hours =
        window.end.difference(window.start).inSeconds / Duration.secondsPerHour;
    return cycle.excessUnitsPerHour * hours;
  }

  /// The stretch a cycle actually delivered over, clipped to the window asked
  /// for and to now, and capped at the fuse.
  ///
  /// The fuse cap is what makes an abandoned cycle stop counting. Past it the pod
  /// has returned to its schedule on its own, so a cycle nothing replaced must
  /// neither be billed further nor be treated as having decayed from a midpoint
  /// that keeps sliding forward. Getting only the first of those right left a
  /// four-hour-old cycle claiming a third of its insulin was still on board.
  ({DateTime start, DateTime end})? _windowOf(
    PodLoopCycle cycle,
    DateTime from,
    DateTime to,
    DateTime now,
  ) {
    final expiry = cycle.at.add(LoopLimits.fuse);
    var end = to.isBefore(now) ? to : now;
    if (end.isAfter(expiry)) {
      end = expiry;
    }
    if (!end.isAfter(from)) {
      return null;
    }
    return (start: from, end: end);
  }
}
