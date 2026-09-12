import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' show Response;
import 'package:insulink/src/google_health/intraday_pulse_store.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// Mirrors the granular intraday pulse curve to the user's backend account and
/// pulls it back on sign-in, so the curve can be reconstructed from the account
/// alone — no Health Connect needed. Unlike the day-archive sync this is
/// incremental and merge-by-minute: [push] debounces sending just the touched
/// days' minute buckets (the server upserts by minute-epoch), which keeps the
/// live pulse flowing up without re-uploading months of history each time.
///
/// Two speeds, on purpose: [push] carries the durable curve at the resolution it
/// is stored in (one point per minute), while [pushLive] relays the current bpm
/// every second into a server-side cache that is never written to the database.
/// A value that is worthless one second later does not deserve a row.
class PulseSync {
  static const _store = IntradayPulseStore();

  /// Live relay cadence. While a viewer is actually watching (the panel's
  /// running-routine vitals bar polls the server ~1 Hz) the bpm is worth 1 Hz;
  /// otherwise a 1 Hz HTTPS relay would pin the cellular radio in its high-power
  /// state around the clock — the single biggest background battery cost — so we
  /// drop to a slow keepalive that still lets us notice a viewer appearing.
  ///
  /// Demand is driven by the server, not by local workout state: the push
  /// response carries whether a viewer polled recently ([_liveViewer]). That is
  /// the only signal that works when the workout runs on the panel while the app
  /// is closed — the phone never sees such a session locally.
  static const _liveActiveEvery = Duration(seconds: 1);
  static const _liveIdleEvery = Duration(seconds: 20);

  static Timer? _timer;
  static DateTime? _lastLiveSend;
  static bool _liveInFlight = false;
  static bool _liveViewer = false;
  static final Set<String> _dirtyDays = {};

  /// Relays the band's current bpm so the user's other devices — the web panel's
  /// workout vitals bar — can show it about a second later. This is a relay, not
  /// a sync: the backend caches the value in memory and never stores it, because
  /// the durable curve already travels via [push] once a minute.
  ///
  /// Throttled, not debounced: at ~1 Hz a debounce would keep resetting and only
  /// fire once the pulse stopped arriving — the exact opposite of live.
  ///
  /// Skipped entirely while one is still in flight. [Request] retries a failed
  /// send with backoff on a 10 s timeout, so on a slow network a plain 1 Hz
  /// fire-and-forget would stack requests faster than they drain. Dropping a
  /// beat costs nothing — the next one is a second away and carries a better
  /// value than the one we would have queued.
  void pushLive(int bpm) {
    final every = _liveViewer ? _liveActiveEvery : _liveIdleEvery;
    final now = DateTime.now();
    final last = _lastLiveSend;
    if (_liveInFlight || (last != null && now.difference(last) < every)) {
      return;
    }
    _lastLiveSend = now;
    _liveInFlight = true;
    unawaited(
      Request.post(url: '/health/pulse/live/push/', body: {'b': bpm})
          .send(null)
          .then(_adoptViewerFlag)
          .whenComplete(() => _liveInFlight = false),
    );
  }

  /// Whether the server reported a live viewer on the last [pushLive] response —
  /// callers that pick their own sync cadence read the same signal.
  bool get liveViewer => _liveViewer;

  /// Reads the push response's `live` flag: true while a device is polling the
  /// server's live pulse (the panel's running-routine vitals bar). Drives the
  /// [pushLive] cadence, so 1 Hz costs only run while something is watching.
  void _adoptViewerFlag(Response? response) {
    final body = response.jsonObject;
    if (body == null) {
      return;
    }
    _liveViewer = body['live'] == true;
  }

  void push(Set<String> dayKeys) {
    if (dayKeys.isEmpty) {
      return;
    }
    _dirtyDays.addAll(dayKeys);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), _send);
  }

  Future<void> _send() async {
    final days = _dirtyDays.toList();
    _dirtyDays.clear();
    final samples = await _store.samplesForDays(days);
    if (samples.isEmpty) {
      return;
    }
    await Request.post(
      url: '/health/pulse/sync/',
      body: {
        'samples': [
          for (final sample in samples)
            {'t': sample.at.millisecondsSinceEpoch, 'b': sample.bpm},
        ],
      },
    ).send(null);
  }

  /// Adopts the account's pulse samples into the local store on sign-in, so a
  /// returning device can redraw the full curve without Health Connect.
  Future<void> pull(BuildContext? context) async {
    final response = await Request.get(
      url: '/health/pulse/find/',
    ).send(context);
    final body = response.jsonObject;
    if (body == null) {
      return;
    }
    if (body['success'] != true || body['samples'] is! List) {
      return;
    }
    await _store.merge([
      for (final sample in body['samples'] as List)
        (
          at: DateTime.fromMillisecondsSinceEpoch((sample as Map)['t'] as int),
          bpm: sample['b'] as int,
        ),
    ]);
  }
}
