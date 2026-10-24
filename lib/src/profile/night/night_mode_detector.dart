import 'dart:async';

import 'package:insulink/src/profile/night/night_mode.dart';

/// Automatic night mode from the live band pulse, in the service isolate.
///
/// Asleep once every sample for [_sustain] stayed below the user's threshold;
/// awake again at the first sample [_wakeMargin] above it, or when the pulse
/// stops arriving for [_staleAfter] (band off the wrist, out of range, battery
/// saver). Losing the pulse ends night mode on purpose: without it nothing says
/// the wearer still sleeps, and the safe direction is a ringing phone.
///
/// ponytail: pulse only, as asked. Adding the clock (only between 21 and 9 h)
/// would cut false positives from a calm afternoon on the sofa if they show up.
class NightModeDetector {
  static const _sustain = Duration(minutes: 20);
  static const _staleAfter = Duration(minutes: 10);
  static const _wakeMargin = 10;

  int _threshold = NightMode.pulseThreshold.defaultValue;
  DateTime? _belowSince;
  DateTime? _lastSampleAt;
  /// Null until the first verdict, so that one is always written: a stored
  /// "asleep" left over from before a service restart must not linger.
  bool? _asleep;

  bool get asleep => _asleep ?? false;

  /// Called from the watchdog tick: picks up a changed threshold and ends
  /// night mode when the pulse has gone quiet.
  Future<void> refresh(DateTime now) async {
    _threshold = await NightMode.pulseThreshold.load();
    final last = _lastSampleAt;
    if (last == null || now.difference(last) > _staleAfter) {
      _belowSince = null;
      _set(false);
    }
  }

  void onPulse(int bpm, DateTime at) {
    _lastSampleAt = at;
    if (bpm >= _threshold) {
      _belowSince = null;
      if (bpm >= _threshold + _wakeMargin) {
        _set(false);
      }
      return;
    }
    final since = _belowSince ??= at;
    if (at.difference(since) >= _sustain) {
      _set(true);
    }
  }

  void _set(bool asleep) {
    if (asleep == _asleep) {
      return;
    }
    _asleep = asleep;
    unawaited(const NightMode().saveDetected(asleep));
  }
}
