import 'dart:async';

import 'package:insulink/src/activity_mode/activity_mode_settings.dart';
import 'package:insulink/src/activity_mode/activity_mode_store.dart';

/// Endurance from the live band pulse, in the service isolate.
///
/// Active once the pulse has stayed at or above the user's threshold for
/// [sustain]; from then on every sample at or above it renews the sighting,
/// which [ActivityModeStore] counts for its usual ten minutes. A single sample
/// a little under the line does not restart the clock, only one [_dropMargin]
/// below it does, because a pulse at the line wobbles around it.
class ActivityPulseDetector {
  static const sustain = Duration(minutes: 10);
  static const _dropMargin = 10;

  int _threshold = ActivityModeSettings.pulseThreshold.defaultValue;
  DateTime? _aboveSince;

  /// Picks up a changed threshold; called from the watchdog tick.
  Future<void> refresh() async {
    _threshold = await ActivityModeSettings.pulseThreshold.load();
  }

  void onPulse(int bpm, DateTime at) {
    if (bpm < _threshold - _dropMargin) {
      _aboveSince = null;
      return;
    }
    if (bpm < _threshold) {
      return;
    }
    final since = _aboveSince ??= at;
    if (at.difference(since) >= sustain) {
      unawaited(const ActivityModeStore().markPulse(at));
    }
  }
}
