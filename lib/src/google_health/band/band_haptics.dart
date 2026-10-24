import 'package:fitbit_air/fitbit_air.dart';
import 'package:flutter/foundation.dart';
import 'package:insulink/src/google_health/band/band_vibration_pattern.dart';
import 'package:insulink/src/profile/notifications/alarm_tone.dart';

/// Buzzes the Fitbit Air on the wrist through the `fitbit_air` plugin, in the
/// pattern of each alarm ([BandVibrationPattern]).
///
/// Every pulse group is one plugin command of a few seconds (a secure session
/// next to Google Health's), so alarm callers run this unawaited and it never
/// holds up the notification or the tone. Nothing here throws: no band paired,
/// no plugin on web and no Bluetooth permission all read as "not felt".
class BandHaptics {
  /// How often a temporary failure (band busy, Google Health holding the
  /// channel, briefly out of range) is tried again. A second buzz after an
  /// ambiguous timeout is harmless for an alarm; a missed one is not.
  static const _attempts = 3;
  static const _retryDelay = Duration(seconds: 10);

  /// Buzz [slot]'s pattern unless the user switched it off for that alarm.
  /// Returns whether the whole pattern reached the band.
  Future<bool> play(AlarmSlot slot) async {
    if (!await slot.bandSetting.load()) {
      return false;
    }
    return preview(slot);
  }

  /// Buzz [slot]'s pattern regardless of its switch, for the settings preview.
  Future<bool> preview(AlarmSlot slot) async {
    for (var group = 0; group < slot.pulseGroups; group++) {
      if (!await _pulseGroup(slot.doublePulse)) {
        return false;
      }
    }
    return true;
  }

  /// Two pulses once, the plain "is the band reachable" test.
  Future<bool> vibrate() => _pulseGroup(true);

  Future<bool> _pulseGroup(bool doublePulse) async {
    for (var attempt = 1; attempt <= _attempts; attempt++) {
      final failure = await _tryPulse(doublePulse);
      if (failure == null) {
        return true;
      }
      if (failure != AirFailureKind.temporary || attempt == _attempts) {
        return false;
      }
      await Future<void>.delayed(_retryDelay);
    }
    return false;
  }

  /// One attempt: null on success, else how it failed.
  Future<AirFailureKind?> _tryPulse(bool doublePulse) async {
    try {
      await (doublePulse ? FitbitAir.vibrate() : FitbitAir.tap());
      return null;
    } on FitbitAirException catch (error) {
      debugPrint('[band] pulse failed: $error');
      return error.kind;
    } catch (error) {
      debugPrint('[band] pulse unavailable: $error');
      return AirFailureKind.unknown;
    }
  }
}
