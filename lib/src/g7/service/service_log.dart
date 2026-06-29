import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persistent on-device log that survives isolate AND process restarts.
///
/// The service isolate's `sendDataToMain` log lines go nowhere when the app is
/// closed (no UI isolate is listening), so overnight watchdog activity — exactly
/// the recovery path we need to debug — was lost. This appends those lines to a
/// capped file in the app's internal storage that the UI reads back on launch.
/// `path_provider` resolves the same directory in both isolates.
class ServiceLog {
  File? _file;

  /// ponytail: 256 KB ring — past this the oldest half is dropped. Days of
  /// watchdog lines fit; bump if a single session needs longer history.
  static const _maxBytes = 256 * 1024;

  Future<File> _resolve() async {
    final cached = _file;
    if (cached != null) {
      return cached;
    }
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/g7_service.log');
    _file = file;
    return file;
  }

  /// Append one timestamped line, then trim the oldest half if the file has
  /// grown past [_maxBytes]. Best-effort: logging must never crash the service.
  Future<void> append(String line) async {
    try {
      final file = await _resolve();
      await file.writeAsString(
        '${DateTime.now().toIso8601String()}  $line\n',
        mode: FileMode.append,
        flush: true,
      );
      await _trimIfLarge(file);
    } catch (_) {}
  }

  Future<void> _trimIfLarge(File file) async {
    if (await file.length() <= _maxBytes) {
      return;
    }
    final kept = await file.readAsString();
    await file.writeAsString(kept.substring(kept.length - _maxBytes ~/ 2));
  }

  /// The whole log oldest-line-first, or empty if nothing has been written yet.
  Future<String> readAll() async {
    try {
      final file = await _resolve();
      return await file.exists() ? await file.readAsString() : '';
    } catch (_) {
      return '';
    }
  }
}
