import 'package:insulink/src/localization/enum_locale_key.dart';
import 'package:insulink/src/pump/pod_account_history.dart';
import 'package:insulink/src/pump/pod_store.dart';

/// One line of the pod's history: a dose the user chose, a micro bolus the
/// automation gave, a volume the activation consumed, or an hour of basal.
///
/// Basal and doses are stored apart — one is a running drip booked by the
/// background watch, the other a set of discrete events — and are only brought
/// together here, for reading. Merging them earlier would mean a bolus could be
/// lost in three hundred quarter-hour rows, or basal could be counted as a dose.
class PodLogEntry {
  const PodLogEntry._({
    required this.at,
    required this.units,
    required this.labelKey,
    required this.isDose,
    this.spansAnHour = false,
  });

  /// A discrete delivery: a bolus, a micro bolus, or one of the two activation
  /// volumes. A micro bolus is not a dose the user chose, so it is not
  /// [isDose].
  factory PodLogEntry.fromDelivery(PodDelivery delivery) => PodLogEntry._(
    at: delivery.at,
    units: delivery.units,
    labelKey: 'pump.log.kind.${delivery.kind.localeKey}',
    isDose: delivery.kind == PodDeliveryKind.bolus,
  );

  /// One wall-clock hour of basal.
  factory PodLogEntry.fromBasalHour(PodBasalHour hour) => PodLogEntry._(
    at: hour.hour,
    units: hour.units,
    labelKey: 'pump.log.kind.basal',
    isDose: false,
    spansAnHour: true,
  );

  final DateTime at;
  final double units;
  final String labelKey;

  /// Whether this insulin went into the user as a dose they asked for. Priming
  /// and cannula volumes did not, and basal is not a dose.
  final bool isDose;

  /// Whether [at] names the start of an hour rather than a moment.
  final bool spansAnHour;

  /// Everything the pod has delivered, newest first.
  ///
  /// An hour of basal sorts by the hour it started, so it sits with the doses
  /// given during it rather than at the end of the list. The account's copy
  /// ([PodAccountHistory]) fills in what the phone lost to a reinstall and the
  /// micro boluses older than the loop ledger's last day.
  static List<PodLogEntry> timeline(
    PodStore store, [
    PodAccountHistory account = const PodAccountHistory(),
  ]) {
    final entries = <PodLogEntry>[
      for (final delivery in account.mergedDeliveries(store))
        PodLogEntry.fromDelivery(delivery),
      for (final hour in account.mergedBasalHours(store))
        PodLogEntry.fromBasalHour(hour),
    ]..sort((left, right) => right.at.compareTo(left.at));
    return entries;
  }
}
