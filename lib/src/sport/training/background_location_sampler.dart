import 'package:geolocator/geolocator.dart';

import '../sport_store.dart';
import 'cardio_models.dart';

/// Periodically samples the position in the foreground-service isolate and
/// appends it to the location log ([SportStore.appendLocationSample]) — the raw
/// material for the cardio auto-detection AND the live route of a manually
/// started training (which records via this same log while backgrounded).
///
/// The cadence is **adaptive**: ~10s while moving or while a training is being
/// recorded, ~60s at rest to save battery. A running training forces high
/// accuracy; a paused training records nothing. Only runs when location is
/// permitted (otherwise silently does nothing); glucose reading never depends on
/// it. `ponytail:` polling via [Geolocator.getCurrentPosition] driven by the
/// service's 10s timer — a continuous stream would only be needed for finer than
/// 10s resolution.
class BackgroundLocationSampler {
  final SportStore _store;
  DateTime? _lastSampledAt;
  Position? _lastFix;

  static const _idleInterval = Duration(seconds: 55);
  static const _movingInterval = Duration(seconds: 10);
  static const _fixTimeout = Duration(seconds: 20);

  /// Above this speed (km/h) the last fix counts as "moving" → fast cadence.
  static const _movingKmh = 3.0;

  BackgroundLocationSampler([this._store = const SportStore()]);

  /// Called by the service's 10s timer; samples at most once per adaptive
  /// interval. Skips entirely while an active training is paused.
  Future<void> tick() async {
    final active = await _store.loadActiveTraining();
    final recording = active != null && !active.isPaused;
    if (active != null && active.isPaused) {
      return;
    }
    final last = _lastSampledAt;
    if (last != null && DateTime.now().difference(last) < _interval(recording)) {
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
        locationSettings: LocationSettings(
          accuracy: recording
              ? LocationAccuracy.high
              : LocationAccuracy.medium,
        ),
      ).timeout(_fixTimeout);
      _lastFix = fix;
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

  /// Fast cadence while recording a training or while the last fix showed
  /// movement; slow cadence otherwise.
  Duration _interval(bool recording) {
    if (recording || _isMoving) {
      return _movingInterval;
    }
    return _idleInterval;
  }

  bool get _isMoving {
    final speed = _lastFix?.speed ?? 0;
    return speed > 0 && speed * 3.6 >= _movingKmh;
  }
}
