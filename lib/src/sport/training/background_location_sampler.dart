import 'package:geolocator/geolocator.dart';

import '../sport_store.dart';
import 'cardio_models.dart';

/// Periodically (~60s) samples the position in the foreground-service isolate
/// and appends it to the location log ([SportStore.appendLocationSample]) —
/// independent of the G7 reader, as raw material for later location features.
///
/// Only runs when location permission is granted (otherwise silently does
/// nothing); in the location-typed foreground service, "while in use" suffices
/// even with the screen off. `ponytail:` — deliberately simple polling via
/// [Geolocator.getCurrentPosition]; a continuous stream would only be needed
/// once a feature requires finer resolution than 60s.
class BackgroundLocationSampler {
  final SportStore _store;
  DateTime? _lastSampledAt;

  static const _minInterval = Duration(seconds: 55);
  static const _fixTimeout = Duration(seconds: 20);

  BackgroundLocationSampler([this._store = const SportStore()]);

  /// Called by the watchdog every pass; samples at most every ~60s.
  Future<void> tick() async {
    final last = _lastSampledAt;
    if (last != null && DateTime.now().difference(last) < _minInterval) {
      return;
    }
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return;
      }
      _lastSampledAt = DateTime.now();
      final fix = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(_fixTimeout);
      await _store.appendLocationSample(
        TrackPoint(
          lat: fix.latitude,
          lng: fix.longitude,
          tMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (_) {
      // ponytail: best-effort; a failed/timed-out fix just skips this tick and
      // retries on the next one.
    }
  }
}
