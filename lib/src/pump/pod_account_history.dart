import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// The current pod's deliveries as the account holds them, merged with the
/// local log so the pump's list and totals survive a reinstall.
///
/// The local log is wiped with the app's data; the account keeps every bolus,
/// prime, cannula volume and micro bolus ([PodHistorySync]) and every basal
/// window ([InsulinSync]). Only what happened since the pod was activated is
/// read back, because the list and its totals are about this pod. Local wins
/// wherever both know a delivery, since it may hold a correction not yet pushed.
class PodAccountHistory {
  const PodAccountHistory({
    this.deliveries = const [],
    this.basalSamples = const [],
  });

  final List<PodDelivery> deliveries;
  final List<({DateTime at, double units})> basalSamples;

  /// Reads both logs; an unreachable account reads as empty, never as an error,
  /// so the page still shows what the phone knows.
  static Future<PodAccountHistory> load(DateTime? activatedAt) async {
    if (activatedAt == null) {
      return const PodAccountHistory();
    }
    final deliveries = await _fetch('/insulin/delivery/find/');
    final basal = await _fetch('/insulin/basal/find/');
    bool sincePod(Map<String, dynamic> entry) =>
        (entry['at'] as num).toInt() >= activatedAt.millisecondsSinceEpoch;
    return PodAccountHistory(
      deliveries: [
        for (final entry in deliveries.where(sincePod))
          PodDelivery.fromJson(entry),
      ],
      basalSamples: [
        for (final entry in basal.where(sincePod))
          (
            at: DateTime.fromMillisecondsSinceEpoch((entry['at'] as num).toInt()),
            units: (entry['units'] as num).toDouble(),
          ),
      ],
    );
  }

  static Future<List<Map<String, dynamic>>> _fetch(String path) async {
    try {
      final response = await Request.get(url: path).send(null);
      final body = response.jsonObject;
      if (body == null || body['success'] != true) {
        return const [];
      }
      return (body['deliveries'] as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  /// The pod's deliveries (not basal), local first, plus the account's entries
  /// the phone no longer holds.
  List<PodDelivery> mergedDeliveries(PodStore store) {
    final local = [...store.deliveryLog, ...store.loopMicroBoluses];
    final known = {for (final entry in local) _key(entry)};
    return [
      ...local,
      for (final entry in deliveries)
        if (!known.contains(_key(entry))) entry,
    ];
  }

  /// Basal per wall-clock hour. Each side sums the same quarter-hour windows,
  /// so the larger figure is the more complete one.
  List<PodBasalHour> mergedBasalHours(PodStore store) {
    final hours = <DateTime, double>{};
    for (final sample in basalSamples) {
      final hour = DateTime(
        sample.at.year,
        sample.at.month,
        sample.at.day,
        sample.at.hour,
      );
      hours[hour] = (hours[hour] ?? 0) + sample.units;
    }
    for (final local in store.basalHours) {
      final remote = hours[local.hour] ?? 0;
      hours[local.hour] = local.units > remote ? local.units : remote;
    }
    return [
      for (final entry in hours.entries)
        PodBasalHour(hour: entry.key, units: entry.value),
    ];
  }

  /// This pod's basal: the local running total, or the account's sum after a
  /// reinstall reset it.
  double basalTotal(PodStore store) {
    final remote = basalSamples.fold(0.0, (sum, sample) => sum + sample.units);
    final local = store.basalDeliveredTotal;
    return local > remote ? local : remote;
  }

  /// This pod's micro boluses, by the same rule as [basalTotal].
  double microBolusTotal(PodStore store) {
    final remote = deliveries
        .where((entry) => entry.kind == PodDeliveryKind.microBolus)
        .fold(0.0, (sum, entry) => sum + entry.units);
    final local = store.loopMicroBolusTotal;
    return local > remote ? local : remote;
  }

  String _key(PodDelivery delivery) =>
      '${delivery.kind.name}@${delivery.at.millisecondsSinceEpoch}';
}
