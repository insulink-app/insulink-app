import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Which replace-all collections hold local changes the account has not
/// confirmed yet, persisted so it survives a restart.
///
/// The pulls REPLACE a collection with the account's copy. The in-memory guard
/// each sync keeps only covers a push still on its way; a push that failed (no
/// network, or no account yet) used to be forgotten, and the next pull then
/// silently reverted the change. With the mark on disk, a pull of a marked
/// collection MERGES instead and pushes the union back up.
///
/// ponytail: a merge keeps every item either side has, so an item deleted
/// offline comes back once. Per-item tombstones if that ever matters.
class SyncLedger {
  static const _storage = FlutterSecureStorage();
  static const _prefix = 'sync_dirty.';

  const SyncLedger();

  Future<void> mark(String collection) =>
      _storage.write(key: '$_prefix$collection', value: 'true');

  Future<void> clear(String collection) =>
      _storage.delete(key: '$_prefix$collection');

  Future<bool> isDirty(String collection) async =>
      await _storage.read(key: '$_prefix$collection') == 'true';

  /// Writes the account's [remote] copy of [collection] through [save]: as is
  /// when nothing local is pending, else merged with [local] (local wins on the
  /// same [keyOf]). True when it merged, so the caller pushes the union.
  Future<bool> adopt<T>({
    required String collection,
    required List<T> remote,
    required Future<List<T>> Function() local,
    required Future<void> Function(List<T>) save,
    required Object Function(T) keyOf,
  }) async {
    if (!await isDirty(collection)) {
      await save(remote);
      return false;
    }
    await save(merge(await local(), remote, keyOf));
    return true;
  }

  /// [local] plus every [remote] item whose key [local] does not have.
  List<T> merge<T>(List<T> local, List<T> remote, Object Function(T) keyOf) {
    final known = {for (final item in local) keyOf(item)};
    return [
      ...local,
      for (final item in remote)
        if (!known.contains(keyOf(item))) item,
    ];
  }
}
