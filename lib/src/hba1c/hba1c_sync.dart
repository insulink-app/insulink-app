import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:insulink/src/hba1c/hba1c_entry.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// Mirrors the HbA1c readings to the user's backend account (`/health/hba1c/…`,
/// its own table) and pulls them back on sign-in.
///
/// [push] debounces a best-effort send of the whole local list; the server MERGES
/// by timestamp and never deletes on a push, so a device that holds only part of
/// the history cannot wipe the rest. That is also why a deletion needs its own
/// [remove] call — dropping the entry locally and re-pushing would leave the
/// server row untouched. Mirrors `SportSync`'s measurement handling.
class Hba1cSync {
  static Timer? _timer;

  void push(List<Hba1cEntry> entries) {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () => _send(entries));
  }

  Future<void> _send(List<Hba1cEntry> entries) async {
    await Request.post(
      url: '/health/hba1c/sync/',
      body: {
        'readings': [for (final entry in entries) _body(entry)],
      },
    ).send(null);
  }

  /// Deletes exactly [entry] on the account. Called before the push that follows
  /// a delete or a retimed edit, since the merge on the other side never removes.
  Future<void> remove(Hba1cEntry entry) async {
    await Request.post(
      url: '/health/hba1c/delete/',
      body: {
        'readings': [
          {'time': entry.atEpochMs},
        ],
      },
    ).send(null);
  }

  /// The account's readings, or null when the request failed — so the caller can
  /// tell "nothing stored" from "could not ask" and leave local data alone.
  Future<List<Hba1cEntry>?> pull(BuildContext? context) async {
    final response = await Request.get(
      url: '/health/hba1c/find/',
    ).send(context);
    final body = response.jsonObject;
    if (body == null) {
      return null;
    }
    if (body['success'] != true || body['readings'] is! List) {
      return null;
    }
    return [
      for (final reading in body['readings'] as List)
        Hba1cEntry(
          atEpochMs: (reading as Map)['time'] as int,
          percent: (reading['percent'] as num).toDouble(),
        ),
    ];
  }

  Map<String, Object> _body(Hba1cEntry entry) => {
    'percent': entry.percent,
    'time': entry.atEpochMs,
  };
}
