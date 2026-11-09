part of 'pod_store.dart';

/// The rest of a split bolus still to be given ([SplitBolusPlan]). Written by
/// the injection page, worked off by the service isolate, so each side has to
/// [PodStore.reload] to see the other's writes.
extension PodSplitBolus on PodStore {
  SplitBolusPlan? get splitBolus {
    final encoded = _cache[PodStore._kSplitBolus];
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      return SplitBolusPlan.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> saveSplitBolus(SplitBolusPlan plan) =>
      _set(PodStore._kSplitBolus, jsonEncode(plan.toJson()));

  Future<void> clearSplitBolus() => _remove(PodStore._kSplitBolus);
}
