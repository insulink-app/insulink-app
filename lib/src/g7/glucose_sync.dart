import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:insulink/src/g7/store.dart';
import 'package:insulink/src/request/request.dart';

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
    final status = await report(batch);
    onLog('glucose report: ${batch.length} value(s) → status $status');
    if (status == null) {
      _retryLater(batch, onLog);
    } else if (status >= 200 && status < 300) {
      _markReported(batch.keys);
    }
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

  /// A null status means the POST never reached the server (radio asleep in the
  /// background). Each minute-reading is only queued once, so without this the
  /// batch would be lost. Put it back (without clobbering newer values for the
  /// same minute) and re-arm a slower flush so it retries on the next wake.
  void _retryLater(Map<int, int> batch, void Function(String) onLog) {
    batch.forEach((minute, value) => _pending.putIfAbsent(minute, () => value));
    while (_pending.length > _retryCap) {
      _pending.remove(_pending.keys.first);
    }
    _flush?.cancel();
    _flush = Timer(const Duration(seconds: 30), () => _send(onLog));
  }

  /// Caps the retry buffer during a long backend outage. The archive stays the
  /// source of truth, so a returning device resyncs via [pullHistory] on login.
  static const int _retryCap = 5000;

  /// Report readings (epoch-minute → mg/dL) to the backend. Runs in the service
  /// isolate, so it passes a null context: [Request] still attaches the stored
  /// bearer token but skips its UI-only 403/417 recovery. Returns the HTTP status
  /// (null on network failure) so the caller can log the outcome. Best-effort —
  /// the next reading/backfill re-sends.
  Future<int?> report(Map<int, int> byEpochMinute) async {
    if (byEpochMinute.isEmpty) {
      return null;
    }
    final entries = byEpochMinute.entries
        .map((entry) => {"glucose": entry.value, "time": _time(entry.key)})
        .toList();
    final response = await Request.post(
      url: "/glucose/report/",
      body: {"entries": entries},
    ).send(null);
    return response?.statusCode;
  }

  /// Pull the account's stored readings into the local archive (on sign-in).
  Future<void> pullHistory(BuildContext context) async {
    final response = await Request.get(url: "/glucose/history/").send(context);
    if (response == null) {
      return;
    }
    final body = jsonDecode(response.body);
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
    final store = await G7Store.open();
    await store.archiveAddAll(readings);
  }
}
