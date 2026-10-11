import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/cgm/cgm_store.dart';
import 'package:insulink/src/cgm/glucose_sync.dart';

/// Uploads every archived reading the account has not confirmed yet.
///
/// [GlucoseSync.queue] only holds readings in memory, so a long outage (no
/// network, or no account at all) followed by a service restart lost them for
/// the account: the device kept them, nothing sent them again. This keeps a
/// persisted mark, the newest epoch minute the account has accepted, and sends
/// the archive past it oldest first, in chunks, advancing the mark per accepted
/// chunk. The server dedups by minute, so overlap with the live queue is harmless.
class GlucoseBacklog {
  static const _storage = FlutterSecureStorage();
  static const _markKey = 'glucose_sync.uploaded_through';
  static const _chunkSize = 500;
  static const _retention = Duration(days: 90);

  /// How often a drain may start. The live queue covers the minutes as they
  /// arrive; this only has to catch what it lost.
  static const _interval = Duration(minutes: 15);

  DateTime? _lastRun;
  bool _running = false;

  /// Drains when the last run is at least [_interval] ago.
  Future<void> drainIfDue(CgmStore store, void Function(String) onLog) async {
    final now = DateTime.now();
    final last = _lastRun;
    if (_running || (last != null && now.difference(last) < _interval)) {
      return;
    }
    _lastRun = now;
    _running = true;
    try {
      await _drain(store, onLog);
    } finally {
      _running = false;
    }
  }

  /// Sends chunk after chunk until the archive is caught up or a chunk fails.
  Future<void> _drain(CgmStore store, void Function(String) onLog) async {
    var sent = 0;
    while (true) {
      final chunk = await _nextChunk(store);
      if (chunk.isEmpty) {
        break;
      }
      final (status, error) = await GlucoseSync().report(chunk);
      if (status == null || status < 200 || status >= 300) {
        onLog('glucose backlog: stopped after $sent, status $status $error');
        return;
      }
      await _storage.write(key: _markKey, value: '${chunk.keys.last}');
      sent += chunk.length;
    }
    if (sent > 0) {
      onLog('glucose backlog: $sent reading(s) caught up');
    }
  }

  /// The oldest [_chunkSize] archived readings past the mark, never further
  /// back than the archive keeps.
  Future<Map<int, int>> _nextChunk(CgmStore store) async {
    final now = DateTime.now();
    final mark = int.tryParse(await _storage.read(key: _markKey) ?? '');
    final floor = now.subtract(_retention);
    final from = mark == null
        ? floor
        : DateTime.fromMillisecondsSinceEpoch((mark + 1) * 60000);
    final range = store.archiveRange(from.isBefore(floor) ? floor : from, now);
    return Map.fromEntries(range.entries.take(_chunkSize));
  }
}
