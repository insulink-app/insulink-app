import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'trash_entry.dart';

/// The deleted entries of this device, kept for [_keep] so a mistaken delete
/// can be undone. Local only: the account already lost the entry on the next
/// sync, and a restore puts it back through that same sync.
class TrashStore {
  static const _key = 'trash.entries';
  static const _keep = Duration(days: 30);
  static const _cap = 300;
  static const _storage = FlutterSecureStorage();

  const TrashStore();

  /// Puts a copy of something just deleted into the trash.
  Future<void> keep(TrashKind kind, Map<String, dynamic> data) async {
    final entries = await load()
      ..add(
        TrashEntry(
          kind: kind,
          deletedAtMs: DateTime.now().millisecondsSinceEpoch,
          data: data,
        ),
      );
    await _save(entries);
  }

  /// The entries still in the trash, oldest deletion first; anything past
  /// [_keep] is gone.
  Future<List<TrashEntry>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) {
      return [];
    }
    final cutoff = DateTime.now().subtract(_keep).millisecondsSinceEpoch;
    return [
      for (final json in jsonDecode(raw) as List)
        TrashEntry.fromJson((json as Map).cast()),
    ].where((entry) => entry.deletedAtMs >= cutoff).toList();
  }

  /// Takes an entry out of the trash, once it is restored.
  Future<void> take(TrashEntry taken) async {
    final entries = await load()
      ..removeWhere(
        (entry) =>
            entry.kind == taken.kind && entry.deletedAtMs == taken.deletedAtMs,
      );
    await _save(entries);
  }

  Future<void> _save(List<TrashEntry> entries) async {
    final kept = entries.length > _cap
        ? entries.sublist(entries.length - _cap)
        : entries;
    await _storage.write(
      key: _key,
      value: jsonEncode([for (final entry in kept) entry.toJson()]),
    );
  }
}
