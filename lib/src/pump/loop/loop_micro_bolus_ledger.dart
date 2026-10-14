part of '../pod_store.dart';

/// Every micro bolus the automation gave, so it counts as insulin on board.
///
/// A ledger of its own rather than entries in the delivery log: one micro bolus
/// every five minutes would fill that log in a day and push the user's own
/// boluses out of it.
///
/// An entry is written BEFORE the command goes out, for the reason the temporary
/// rate is: a lost confirmation then overstates insulin on board, which makes
/// the next cycle ask for less. Only a refusal from the pod takes it back out.
extension LoopMicroBolusLedger on PodStore {
  /// How long an entry is kept. Longer than any insulin duration a user can set.
  static const Duration kept = Duration(hours: 24);

  /// Every booked micro bolus, newest first.
  List<PodDelivery> get loopMicroBoluses {
    final encoded = _cache[PodStore._kLoopMicroBoluses];
    if (encoded == null || encoded.isEmpty) {
      return const [];
    }
    try {
      return [
        for (final entry in jsonDecode(encoded) as List<dynamic>)
          PodDelivery.fromJson(entry as Map<String, dynamic>),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Every micro bolus this pod has given, in units.
  ///
  /// A running sum rather than a sum over the entries, because the entries only
  /// reach back [kept] and a pod lives more than three days. Moved by the same
  /// calls that move the entries, and cleared with the pod.
  double get loopMicroBolusTotal =>
      double.tryParse(_cache[PodStore._kLoopMicroBolusTotal] ?? '') ?? 0;

  Future<void> _addToLoopMicroBolusTotal(double units) => _set(
    PodStore._kLoopMicroBolusTotal,
    '${(loopMicroBolusTotal + units).clamp(0.0, double.infinity)}',
  );

  /// Books [units] given at [at], dropping entries past [kept].
  Future<void> bookLoopMicroBolus(double units, DateTime at) async {
    final cutoff = at.subtract(kept);
    await _addToLoopMicroBolusTotal(units);
    await _saveLoopMicroBoluses([
      PodDelivery(at: at, units: units, kind: PodDeliveryKind.microBolus),
      ...loopMicroBoluses.where((entry) => entry.at.isAfter(cutoff)),
    ]);
  }

  /// Takes back the entry booked at [at], for a micro bolus the pod refused.
  Future<void> unbookLoopMicroBolus(DateTime at) async {
    await _addToLoopMicroBolusTotal(-_unitsBookedAt(at));
    await _saveLoopMicroBoluses([
      for (final entry in loopMicroBoluses)
        if (entry.at != at) entry,
    ]);
  }

  double _unitsBookedAt(DateTime at) => loopMicroBoluses
      .where((entry) => entry.at == at)
      .fold(0.0, (sum, entry) => sum + entry.units);

  /// Corrects the entry booked at [at] to [units], for a micro bolus the user
  /// stopped part-way.
  Future<void> amendLoopMicroBolus(DateTime at, double units) async {
    await _addToLoopMicroBolusTotal(units - _unitsBookedAt(at));
    await _saveLoopMicroBoluses([
      for (final entry in loopMicroBoluses)
        entry.at == at
            ? PodDelivery(at: at, units: units, kind: entry.kind)
            : entry,
    ]);
  }

  /// When the newest micro bolus was booked, or null when none was.
  DateTime? get lastLoopMicroBolusAt => loopMicroBoluses.firstOrNull?.at;

  /// Micro-bolus insulin booked within [window] before [now].
  double loopMicroBolusUnitsWithin(Duration window, {DateTime? now}) {
    final since = (now ?? DateTime.now()).subtract(window);
    return loopMicroBoluses
        .where((entry) => entry.at.isAfter(since))
        .fold(0.0, (sum, entry) => sum + entry.units);
  }

  /// What is left of the micro boluses, decaying linearly over
  /// [insulinDuration] exactly as [ActiveInsulin] decays a bolus.
  double loopMicroBolusIobUnits(Duration insulinDuration, {DateTime? now}) {
    final at = now ?? DateTime.now();
    var units = 0.0;
    for (final entry in loopMicroBoluses) {
      final elapsed = at.difference(entry.at).inSeconds;
      final fraction = 1 - elapsed / insulinDuration.inSeconds;
      units += entry.units * fraction.clamp(0.0, 1.0);
    }
    return units;
  }

  /// What is left at [at] of the micro boluses given by then, for a graph that
  /// samples the past. Unlike [loopMicroBolusIobUnits], a micro bolus given
  /// after [at] counts nothing rather than in full.
  double loopMicroBolusIobAt(Duration insulinDuration, DateTime at) {
    var units = 0.0;
    for (final entry in loopMicroBoluses) {
      if (entry.at.isAfter(at)) {
        continue;
      }
      final elapsed = at.difference(entry.at).inSeconds;
      final fraction = 1 - elapsed / insulinDuration.inSeconds;
      units += entry.units * fraction.clamp(0.0, 1.0);
    }
    return units;
  }

  Future<void> _saveLoopMicroBoluses(List<PodDelivery> entries) => _set(
    PodStore._kLoopMicroBoluses,
    jsonEncode([for (final entry in entries) entry.toJson()]),
  );
}
