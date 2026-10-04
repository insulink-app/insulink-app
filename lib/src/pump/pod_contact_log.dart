part of 'pod_store.dart';

/// When the app actually reached the pod, kept as a short history rather than
/// only as the newest moment.
///
/// [PodStore.lastSeenAt] answers "is contact stale right now", which is what the
/// pod warnings need, and it cannot answer "when did contact break", which is
/// what the connection page draws. Nothing else can answer it either: the pod
/// keeps no log and reports no outage, so the only record of a link that worked
/// is the app noting each time it used one.
///
/// Written by [PodStore.markSeen], so every path that reaches the pod records it
/// without having to remember to.
extension PodContactLog on PodStore {
  /// Roughly two days at the background poll's 15-minute cadence. The page shows
  /// one day; the rest is slack for a poll that ran more often (an open pump
  /// page, an automation cycle) so the day on screen is never short.
  static const int _contactCap = 250;

  /// Contact moments as epoch-MINUTES, oldest first. Minutes rather than
  /// milliseconds because that is the resolution the page buckets to anyway, and
  /// it keeps the stored line short.
  List<int> get contactMinutes {
    final raw =
        _cache[PodStore._kContactLog] ?? _cache[PodStore._kLegacyContactLog];
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    return [for (final part in raw.split(',')) ?int.tryParse(part)];
  }

  /// Append one contact, dropping the oldest once the cap is reached.
  ///
  /// A repeat within the same minute is skipped: the automation and the pod
  /// watch can both reach the pod on the same tick, and two entries for one
  /// minute say nothing the first does not.
  Future<void> _appendContact(DateTime at) async {
    final minute = at.millisecondsSinceEpoch ~/ 60000;
    final minutes = contactMinutes;
    if (minutes.isNotEmpty && minutes.last == minute) {
      return;
    }
    final kept = [...minutes, minute];
    if (kept.length > _contactCap) {
      kept.removeRange(0, kept.length - _contactCap);
    }
    await _set(PodStore._kContactLog, kept.join(','));
    if (_cache.containsKey(PodStore._kLegacyContactLog)) {
      await _remove(PodStore._kLegacyContactLog);
    }
  }

  /// The newest contact on record, which outlives the pod it was made with:
  /// after a pod change the page still says when the pump was last heard from
  /// instead of claiming it never was.
  DateTime? get lastContact {
    final minutes = contactMinutes;
    return minutes.isEmpty
        ? null
        : DateTime.fromMillisecondsSinceEpoch(minutes.last * 60000);
  }
}
