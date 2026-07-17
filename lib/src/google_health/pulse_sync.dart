import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:insulink/src/google_health/intraday_pulse_store.dart';
import 'package:insulink/src/request/request.dart';

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

  /// How often the live bpm is relayed. The band delivers ~1 Hz and the panel
  /// reads at the same rate, so anything slower is visibly laggy and anything
  /// faster sends the same number twice.
  static const _liveEvery = Duration(seconds: 1);

  static Timer? _timer;
  static DateTime? _lastLiveSend;
  static bool _liveInFlight = false;
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
    final now = DateTime.now();
    final last = _lastLiveSend;
    if (_liveInFlight || (last != null && now.difference(last) < _liveEvery)) {
      return;
    }
    _lastLiveSend = now;
    _liveInFlight = true;
    unawaited(
      Request.post(
        url: '/health/pulse/live/push/',
        body: {'b': bpm},
      ).send(null).whenComplete(() => _liveInFlight = false),
    );
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
    if (response == null) {
      return;
    }
    final body = jsonDecode(response.body);
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
