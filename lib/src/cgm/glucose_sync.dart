import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:insulink/src/cgm/cgm_store.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// Keeps the on-device glucose record and the backend account in step.
///
/// [queue] runs in the foreground-service isolate — which has no UI context for
/// the token-refresh path — so it posts directly with the stored token and is
/// best-effort. [pullHistory] runs in the UI isolate on sign-in and merges the
/// account's stored readings into the local archive, so a returning device shows
/// its full history.
class GlucoseSync {
  /// Backend `time` is minute-aligned epoch ms, matching the archive's per-minute
  /// dedup: re-reporting a reading (a live EGV then its backfill copy, or across
  /// restarts) yields the same key, so the server dedups it.
  static int _time(int epochMinute) => epochMinute * 60000;

  /// Readings waiting to be reported, coalesced across the rapid stream of small
  /// backfill packets so a whole burst (plus the live EGV) goes out as ONE
  /// request instead of dozens of tiny ones. Static: a fresh [GlucoseSync] is
  /// built per call, but the buffer lives for the isolate.
  static final Map<int, int> _pending = {};
  static Timer? _flush;

  /// Minutes already accepted by the backend, so a re-offered reading (the live
  /// EGV then its backfill copy, or the hourly full-day sweep) isn't re-POSTed.
  /// In-memory like [_pending]: a fresh isolate re-sends once, which the server
  /// dedups. Bounded by [_reportedCap].
  static final Set<int> _reported = {};
  static const int _reportedCap = 5000;

  /// Entries per POST. A 24 h backfill (~282 points) goes out as a handful of
  /// small requests instead of one large one, so a flaky background radio can
  /// land partial progress and one failing request can't wedge the whole sweep.
  static const int _chunkSize = 60;

  /// Retry delay after a failed flush, doubled each consecutive failure up to
  /// [_backoffCap] (so a backgrounded radio stops hammering every 30 s) and
  /// reset to [_backoffFloor] on any success — the running service isolate then
  /// drains within one cap-interval once the app is foreground again.
  static const Duration _backoffFloor = Duration(seconds: 30);
  static const Duration _backoffCap = Duration(seconds: 300);
  static Duration _backoff = _backoffFloor;

  /// Buffer the readings the backend hasn't accepted yet and (re)arm a short
  /// flush. Each new packet pushes the flush out, so a backfill burst settles
  /// into a single report once it goes quiet.
  void queue(Map<int, int> byEpochMinute, void Function(String) onLog) {
    final fresh = <int, int>{};
    byEpochMinute.forEach((minute, value) {
      if (!_reported.contains(minute)) {
        fresh[minute] = value;
      }
    });
    if (fresh.isEmpty) {
      return;
    }
    _pending.addAll(fresh);
    _flush?.cancel();
    _flush = Timer(const Duration(seconds: 3), () => _send(onLog));
  }

  Future<void> _send(void Function(String) onLog) async {
    if (_pending.isEmpty) {
      return;
    }
    final batch = Map<int, int>.from(_pending);
    _pending.clear();
    final failed = <int, int>{};
    int sent = 0;
    int? lastStatus;
    String? lastError;
    for (final part in chunk(batch, _chunkSize)) {
      final (status, error) = await report(part);
      lastStatus = status;
      lastError = error;
      if (status != null && status >= 200 && status < 300) {
        _markReported(part.keys);
        sent += part.length;
      } else {
        failed.addAll(part);
      }
    }
    onLog(
      'glucose report: $sent/${batch.length} value(s) sent → status $lastStatus'
      '${lastError != null ? ' ($lastError)' : ''}',
    );
    if (sent > 0) {
      _backoff = _backoffFloor;
    }
    if (failed.isNotEmpty) {
      _retryLater(failed, onLog);
    }
  }

  /// Split readings into POST-sized maps, preserving every key/value.
  static List<Map<int, int>> chunk(Map<int, int> values, int size) {
    final chunks = <Map<int, int>>[];
    var current = <int, int>{};
    for (final entry in values.entries) {
      current[entry.key] = entry.value;
      if (current.length >= size) {
        chunks.add(current);
        current = <int, int>{};
      }
    }
    if (current.isNotEmpty) {
      chunks.add(current);
    }
    return chunks;
  }

  /// The backoff after a failure: double, capped at [_backoffCap].
  static Duration nextBackoff(Duration current) {
    final doubled = current * 2;
    return doubled > _backoffCap ? _backoffCap : doubled;
  }

  /// Remember accepted minutes so they're never re-POSTed, trimming the oldest
  /// once over [_reportedCap] (the archive stays the source of truth).
  void _markReported(Iterable<int> minutes) {
    _reported.addAll(minutes);
    if (_reported.length > _reportedCap) {
      final keep = _reported.toList()..sort();
      _reported
        ..clear()
        ..addAll(keep.sublist(keep.length - _reportedCap));
    }
  }

  /// A non-2xx (often null — the POST never reached the server, radio asleep in
  /// the background) means these minutes weren't accepted. Each minute is only
  /// queued once, so without this the batch would be lost. Put it back (without
  /// clobbering newer values for the same minute) and re-arm a [_backoff]-spaced
  /// flush — backing off each consecutive failure so it stops hammering.
  void _retryLater(Map<int, int> batch, void Function(String) onLog) {
    batch.forEach((minute, value) => _pending.putIfAbsent(minute, () => value));
    while (_pending.length > _retryCap) {
      _pending.remove(_pending.keys.first);
    }
    _flush?.cancel();
    _flush = Timer(_backoff, () => _send(onLog));
    _backoff = nextBackoff(_backoff);
  }

  /// Caps the retry buffer during a long backend outage. The archive stays the
  /// source of truth, so a returning device resyncs via [pullHistory] on login.
  static const int _retryCap = 5000;

  /// Report readings (epoch-minute → mg/dL) to the backend. Runs in the service
  /// isolate, so it passes a null context: [Request] still attaches the stored
  /// bearer token but skips its UI-only 403/417 recovery. Returns the HTTP status
  /// (null on network failure) plus [Request.lastError] (the transport exception
  /// when null) so the caller can log WHY, not just "status null". Best-effort —
  /// the next reading/backfill re-sends.
  Future<(int?, String?)> report(Map<int, int> byEpochMinute) async {
    if (byEpochMinute.isEmpty) {
      return (null, null);
    }
    final entries = byEpochMinute.entries
        .map((entry) => {"glucose": entry.value, "time": _time(entry.key)})
        .toList();
    final request = Request.post(
      url: "/glucose/report/",
      body: {"entries": entries},
    );
    final response = await request.send(null);
    return (response?.statusCode, request.lastError);
  }

  /// Pull the account's stored readings into the local archive (on sign-in).
  Future<void> pullHistory(BuildContext? context) async {
    final response = await Request.get(url: "/glucose/history/").send(context);
    final body = response.jsonObject;
    if (body == null) {
      return;
    }
    if (body["success"] != true) {
      return;
    }
    final entries = body["entries"];
    if (entries is! List || entries.isEmpty) {
      return;
    }
    final readings = <DateTime, int>{};
    for (final entry in entries) {
      final time = (entry["time"] as num).toInt();
      readings[DateTime.fromMillisecondsSinceEpoch(time)] =
          (entry["value"] as num).round();
    }
    final store = await CgmStore.open();
    await store.archiveAddAll(readings);
  }
}
