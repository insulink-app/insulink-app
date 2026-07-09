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
class PulseSync {
  static const _store = IntradayPulseStore();
  static Timer? _timer;
  static final Set<String> _dirtyDays = {};

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
  Future<void> pull(BuildContext context) async {
    final response = await Request.get(url: '/health/pulse/find/').send(context);
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
