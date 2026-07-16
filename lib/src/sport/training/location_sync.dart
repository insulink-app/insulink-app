import 'dart:async';

import 'package:insulink/src/request/request.dart';

/// Streams the constantly-sampled GPS fixes ([BackgroundLocationSampler]) to the
/// backend account. Runs in the foreground-service isolate — no UI context for
/// the token-refresh path — so it posts directly with the stored token and is
/// best-effort. Mirrors [GlucoseSync]'s report path: coalesce fixes, flush on a
/// short timer, chunk, and back off on failure so a backgrounded radio stops
/// hammering. The backend dedups by `time`, so a re-sent fix is harmless.
class LocationSync {
  /// A single fix waiting to be reported: `{"lat", "lng", "time"}` (epoch ms).
  /// Static so the buffer lives for the isolate even though a fresh [LocationSync]
  /// is built per call.
  static final List<Map<String, Object>> _pending = [];
  static Timer? _flush;

  /// Fixes per POST — keeps a backlog after an outage landing in small requests.
  static const int _chunkSize = 60;

  /// Caps the buffer during a long backend outage; the oldest fixes are dropped
  /// first (freshest position matters most).
  static const int _pendingCap = 2000;

  static const Duration _backoffFloor = Duration(seconds: 30);
  static const Duration _backoffCap = Duration(seconds: 300);
  static Duration _backoff = _backoffFloor;

  /// How long a queued fix waits before its batch is flushed: once a minute, so
  /// dense (few-second) local sampling reaches the backend as one request per
  /// minute rather than a POST per fix — in every case, recording or not.
  static const Duration _flushInterval = Duration(seconds: 60);

  /// Buffer one fix and arm the batched flush (only if one isn't already armed,
  /// so continuous sampling can't keep pushing it back forever). A burst of dense
  /// fixes settles into a single ~[_flushInterval] report.
  void queue(
    double latitude,
    double longitude,
    int epochMs,
    void Function(String) onLog,
  ) {
    _pending.add({"lat": latitude, "lng": longitude, "time": epochMs});
    while (_pending.length > _pendingCap) {
      _pending.removeAt(0);
    }
    _flush ??= Timer(_flushInterval, () {
      _flush = null;
      _send(onLog);
    });
  }

  Future<void> _send(void Function(String) onLog) async {
    if (_pending.isEmpty) {
      return;
    }
    final batch = List<Map<String, Object>>.from(_pending);
    _pending.clear();
    int sent = 0;
    final failed = <Map<String, Object>>[];
    int? lastStatus;
    String? lastError;
    for (var start = 0; start < batch.length; start += _chunkSize) {
      final part = batch.sublist(
        start,
        start + _chunkSize > batch.length ? batch.length : start + _chunkSize,
      );
      final (status, error) = await _report(part);
      lastStatus = status;
      lastError = error;
      if (status != null && status >= 200 && status < 300) {
        sent += part.length;
      } else {
        failed.addAll(part);
      }
    }
    onLog(
      'location report: $sent/${batch.length} fix(es) sent → status $lastStatus'
      '${lastError != null ? ' ($lastError)' : ''}',
    );
    if (sent > 0) {
      _backoff = _backoffFloor;
    }
    if (failed.isNotEmpty) {
      _retryLater(failed);
    }
  }

  Future<(int?, String?)> _report(List<Map<String, Object>> entries) async {
    final request = Request.post(
      url: "/location/report/",
      body: {"entries": entries},
    );
    final response = await request.send(null);
    return (response?.statusCode, request.lastError);
  }

  /// Put failed fixes back (oldest-first trimmed by [queue]'s cap) and re-arm a
  /// [_backoff]-spaced flush, doubling the delay each consecutive failure.
  void _retryLater(List<Map<String, Object>> batch) {
    _pending.insertAll(0, batch);
    while (_pending.length > _pendingCap) {
      _pending.removeAt(0);
    }
    _flush?.cancel();
    _flush = Timer(_backoff, () {
      _flush = null;
      _send((_) {});
    });
    _backoff = _backoff * 2 > _backoffCap ? _backoffCap : _backoff * 2;
  }
}
