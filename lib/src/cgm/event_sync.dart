import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:insulink/src/cgm/cgm_store.dart';
import 'package:insulink/src/request/request.dart';

/// Mirrors the on-device analysis event log (glucose lows/highs, signal loss,
/// sensor swap/stop) to the backend account, and pulls it back on sign-in.
///
/// Events are rare (a few a day), so unlike `GlucoseSync` this skips the
/// coalescing/backoff machinery: [sync] just re-POSTs the events newer than the
/// last confirmed send. The backend dedups on type+time, so a fresh isolate
/// (mark 0) re-sending the whole capped log is harmless.
class EventSync {
  /// Newest event timestamp (epoch ms) the backend has confirmed, per isolate.
  /// In-memory: a fresh isolate re-sends from 0 once and the server dedups.
  static int _syncedThroughMs = 0;

  /// POST the local events newer than [_syncedThroughMs], advancing the mark on
  /// success. Best-effort: a failure leaves the mark, so the next call retries.
  Future<void> sync(CgmStore store, void Function(String) onLog) async {
    final fresh = store
        .eventsBetween(DateTime.fromMillisecondsSinceEpoch(0), DateTime.now())
        .where((event) => event.time.millisecondsSinceEpoch > _syncedThroughMs)
        .toList();
    if (fresh.isEmpty) {
      return;
    }
    final (status, error) = await report(fresh);
    if (status != null && status >= 200 && status < 300) {
      _syncedThroughMs = fresh
          .map((event) => event.time.millisecondsSinceEpoch)
          .reduce((newest, ts) => ts > newest ? ts : newest);
      onLog('event report: ${fresh.length} event(s) sent → status $status');
    } else {
      onLog(
        'event report failed → status $status'
        '${error != null ? ' ($error)' : ''}',
      );
    }
  }

  /// POST events to the backend. Runs in either isolate; passes a null context
  /// (the service isolate has none) so [Request] attaches the stored token but
  /// skips its UI-only token-refresh path. Returns the HTTP status (null on
  /// network failure) plus [Request.lastError] so the caller can log WHY.
  Future<(int?, String?)> report(
    List<({DateTime time, String type, int? value})> events,
  ) async {
    final entries = events
        .map(
          (event) => {
            'type': event.type,
            // Non-null payload string: the mg/dL value for glucose events,
            // empty otherwise — keeps the backend column NOT NULL.
            'data': event.value != null ? '${event.value}' : '',
            'time': event.time.millisecondsSinceEpoch,
          },
        )
        .toList();
    final request = Request.post(
      url: '/event/report/',
      body: {'entries': entries},
    );
    final response = await request.send(null);
    return (response?.statusCode, request.lastError);
  }

  /// Pull the account's stored events into the local log (on sign-in), so a fresh
  /// install shows the full analysis event history.
  Future<void> pullHistory(BuildContext context) async {
    final response = await Request.get(url: '/event/history/').send(context);
    if (response == null) {
      return;
    }
    final body = jsonDecode(response.body);
    if (body['success'] != true) {
      return;
    }
    final entries = body['entries'];
    if (entries is! List || entries.isEmpty) {
      return;
    }
    final events = <({DateTime time, String type, int? value})>[];
    for (final entry in entries) {
      events.add((
        time: DateTime.fromMillisecondsSinceEpoch(
          (entry['time'] as num).toInt(),
        ),
        type: entry['type'] as String,
        value: _value(entry['data']),
      ));
    }
    final store = await CgmStore.open();
    await store.mergeEvents(events);
  }

  /// The integer payload from the backend's `data` string, or null when empty —
  /// the inverse of the `data` mapping in [report].
  int? _value(Object? data) {
    if (data is! String || data.isEmpty) {
      return null;
    }
    return int.tryParse(data);
  }
}
