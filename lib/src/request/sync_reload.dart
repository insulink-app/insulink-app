import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Runs a pull, then the reload that pushes it into the UI ONLY if the pull
/// actually changed one of [keys].
///
/// A pull that brings identical data (the overwhelmingly common case) otherwise
/// still rewrote the stores, re-`notifyListeners`'d and rebuilt the whole page —
/// which, landing mid-scroll, is the short hitch you feel when a sync arrives.
/// No change ⇒ no reload ⇒ no rebuild ⇒ no hitch.
///
/// [keys] is the exact set the caller's pull writes — NOT the whole store. Two
/// reasons this matters, both learned from doing it the lazy way first:
///
/// 1. `readAll()` decrypts EVERY secure-storage entry, and the glucose archive
///    (`g7.hist.*`, up to ~1440 points/day for weeks) lives in the same store.
///    Decrypting all of it twice per sync was itself the lag.
/// 2. A glucose reading landing from the service isolate every ~5 min changes
///    `g7.*`, so a whole-store compare reported "changed" almost every time and
///    the reload ran anyway — defeating the guard.
///
/// Reading only the caller's own keys (a handful) sidesteps both: the giant
/// archive is never touched, and an unrelated glucose write can't force a reload.
class SyncReload {
  const SyncReload();

  /// [reload] receives the SUBSET of [keys] whose value actually changed, so the
  /// caller can refresh only the affected state instead of every one — a sync
  /// that touched one collection then rebuilds one section, not the whole page.
  /// Not called at all when nothing changed.
  Future<void> ifChanged(
    Iterable<String> keys,
    Future<void> Function() pull,
    Future<void> Function(Set<String> changed) reload,
  ) async {
    final before = await _snapshot(keys);
    await pull();
    final after = await _snapshot(keys);
    final changed = {
      for (final key in keys)
        if (before[key] != after[key]) key,
    };
    if (changed.isNotEmpty) {
      await reload(changed);
    }
  }

  Future<Map<String, String?>> _snapshot(Iterable<String> keys) async {
    const storage = FlutterSecureStorage();
    final entries = await Future.wait(
      keys.map((key) async => MapEntry(key, await storage.read(key: key))),
    );
    return Map.fromEntries(entries);
  }
}
