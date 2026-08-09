import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/hba1c/hba1c_entry.dart';
import 'package:insulink/src/hba1c/hba1c_sync.dart';

/// The user's HbA1c readings, kept sorted oldest-first. Self-persists to secure
/// storage (like the Profile*State classes) and mirrors every change to the
/// account through [Hba1cSync].
///
/// Entries are identified by their timestamp — that is the server's natural key
/// too — so re-adding the same instant corrects the value in place instead of
/// producing a duplicate.
class Hba1cState extends ChangeNotifier {
  static const _key = 'hba1c.readings';
  static const _storage = FlutterSecureStorage();

  final List<Hba1cEntry> _entries;

  Hba1cState(this._entries);

  List<Hba1cEntry> get entries => List.unmodifiable(_entries);

  /// The most recent reading, or null before the first one is entered.
  Hba1cEntry? get latest => _entries.isEmpty ? null : _entries.last;

  /// The reading before [latest], so a screen can show the change without
  /// re-deriving the ordering.
  Hba1cEntry? get previous =>
      _entries.length >= 2 ? _entries[_entries.length - 2] : null;

  Future<void> add(double percent, {required DateTime at}) async {
    _put(Hba1cEntry(atEpochMs: at.millisecondsSinceEpoch, percent: percent));
    await _persist();
    Hba1cSync().push(_entries);
  }

  /// Replaces [original] with a new value and/or timestamp. A changed timestamp
  /// also deletes the old server row: the sync only ever merges, so without this
  /// the previous reading would live on in the account as an orphan.
  Future<void> edit(
    Hba1cEntry original, {
    required double percent,
    required DateTime at,
  }) async {
    _entries.remove(original);
    _put(Hba1cEntry(atEpochMs: at.millisecondsSinceEpoch, percent: percent));
    await _persist();
    if (at.millisecondsSinceEpoch != original.atEpochMs) {
      await Hba1cSync().remove(original);
    }
    Hba1cSync().push(_entries);
  }

  Future<void> remove(Hba1cEntry entry) async {
    _entries.remove(entry);
    await _persist();
    await Hba1cSync().remove(entry);
    Hba1cSync().push(_entries);
  }

  /// Adopts the account's readings on sign-in, keeping anything local the
  /// account has not seen yet (a reading entered while signed out).
  Future<void> adopt(List<Hba1cEntry> fromAccount) async {
    for (final entry in fromAccount) {
      _put(entry);
    }
    await _persist();
  }

  /// Inserts [entry] in timestamp order, replacing any reading already stored at
  /// that exact instant (the natural key), then notifies.
  void _put(Hba1cEntry entry) {
    _entries
      ..removeWhere((stored) => stored.atEpochMs == entry.atEpochMs)
      ..add(entry)
      ..sort((first, second) => first.atEpochMs.compareTo(second.atEpochMs));
    notifyListeners();
  }

  Future<void> _persist() async {
    await _storage.write(
      key: _key,
      value: jsonEncode([for (final entry in _entries) entry.toJson()]),
    );
  }

  static Future<Hba1cState> load() async {
    return Hba1cState(await _read());
  }

  /// Pulls the account's readings and merges them into storage on sign-in, so
  /// the provider tree sees them on its next [load]. Static because the pull runs
  /// before a provider handle exists (like the other sign-in sync pulls).
  static Future<void> pullIntoStorage(BuildContext? context) async {
    final fromAccount = await Hba1cSync().pull(context);
    if (fromAccount == null || fromAccount.isEmpty) {
      return;
    }
    final state = Hba1cState(await _read());
    await state.adopt(fromAccount);
  }

  static Future<List<Hba1cEntry>> _read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) {
      return [];
    }
    final entries = [
      for (final entry in jsonDecode(raw) as List)
        Hba1cEntry.fromJson((entry as Map).cast()),
    ];
    entries.sort((first, second) => first.atEpochMs.compareTo(second.atEpochMs));
    return entries;
  }
}
