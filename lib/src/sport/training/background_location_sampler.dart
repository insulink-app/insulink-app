import 'package:geolocator/geolocator.dart';

import '../sport_store.dart';
import 'cardio_models.dart';
import 'location_sync.dart';

/// Periodically samples the position in the foreground-service isolate and
/// appends it to the location log ([SportStore.appendLocationSample]) — the raw
/// material for the cardio auto-detection AND the live route of a manually
/// started training (which records via this same log while backgrounded).
///
/// The cadence is **adaptive**: ~4s while recording a training (dense route),
/// ~10s while merely moving, ~55s at rest to save battery. A running training
/// forces high accuracy; a paused training records nothing. Fixes are passed
/// through an outlier filter ([isPlausibleFix]) so a poor-accuracy or
/// teleport-jump glitch never lands in the route. Only runs when location is
/// permitted (otherwise silently does nothing); glucose reading never depends on
/// it. `ponytail:` polling via [Geolocator.getCurrentPosition] driven by the
/// service's short timer — a continuous stream would only be needed for finer
/// than [_recordingInterval] resolution.
class BackgroundLocationSampler {
  final SportStore _store;
  final void Function(String) _onLog;
  DateTime? _lastSampledAt;
  Position? _lastFix;

  static const _idleInterval = Duration(seconds: 55);
  static const _movingInterval = Duration(seconds: 10);
  static const _recordingInterval = Duration(seconds: 4);
  static const _fixTimeout = Duration(seconds: 20);

  /// Above this speed (km/h) the last fix counts as "moving" → fast cadence.
  static const _movingKmh = 3.0;

  BackgroundLocationSampler({
    this._store = const SportStore(),
    void Function(String)? onLog,
  }) : _onLog = (onLog ?? _noLog);

  static void _noLog(String _) {}

  /// Called by the service timer; samples at most once per adaptive interval.
  /// Skips entirely while an active training is paused.
  Future<void> tick() async {
    final last = _lastSampledAt;
    if (last != null &&
        DateTime.now().difference(last) < _recordingInterval) {
      return;
    }
    try {
      final active = await _store.loadActiveTraining();
      final recording = active != null && !active.isPaused;
      if (active != null && active.isPaused) {
        return;
      }
      if (last != null &&
          DateTime.now().difference(last) < _interval(recording)) {
        return;
      }
      _lastSampledAt = DateTime.now();
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _onLog('location: permission not granted ($permission)');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _onLog('location: device location services disabled');
        return;
      }
      final fix = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: recording ? LocationAccuracy.high : LocationAccuracy.medium,
        ),
      ).timeout(_fixTimeout);
      final tMs = DateTime.now().millisecondsSinceEpoch;
      // Constant backend tracking wants EVERY real fix, even a coarse one (a
      // 100 m city fix is fine for a position log); the strict cardio outlier
      // filter below only guards the local workout route.
      LocationSync().queue(fix.latitude, fix.longitude, tMs, _onLog);
      if (!_accept(fix)) {
        return;
      }
      _lastFix = fix;
      await _store.appendLocationSample(
        TrackPoint(lat: fix.latitude, lng: fix.longitude, tMs: tMs),
      );
    } catch (error) {
      // ponytail: best-effort; a failed/timed-out fix just skips this tick and
      // retries on the next one — but log it, so "no report at all" is never
      // silent (a throwing loadActiveTraining/getCurrentPosition used to kill
      // every tick with no trace).
      _onLog('location sample error: $error');
    }
  }

  /// Rejects an outlier fix; keeps the previous good fix as the reference so a
  /// single glitch never poisons the next check.
  bool _accept(Position fix) {
    final prev = _lastFix;
    if (prev == null) {
      return isPlausibleFix(accuracyM: fix.accuracy);
    }
    final seconds = fix.timestamp.difference(prev.timestamp).inMilliseconds /
        Duration.millisecondsPerSecond;
    final meters = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      fix.latitude,
      fix.longitude,
    );
    return isPlausibleFix(
      accuracyM: fix.accuracy,
      meters: meters,
      seconds: seconds,
    );
  }

  /// Fast cadence while recording a training; medium while merely moving; slow
  /// at rest.
  Duration _interval(bool recording) {
    if (recording) {
      return _recordingInterval;
    }
    if (_isMoving) {
      return _movingInterval;
    }
    return _idleInterval;
  }

  bool get _isMoving {
    final speed = _lastFix?.speed ?? 0;
    return speed > 0 && speed * 3.6 >= _movingKmh;
  }
}

/// Above this horizontal accuracy (meters) a fix is too vague to trust.
const _maxAccuracyM = 50.0;

/// Above this speed (m/s ≈ 200 km/h) between two fixes the jump is a GPS glitch,
/// not real movement.
const _maxSpeedMps = 55.0;

/// Pure outlier test (extracted so it is testable without a [Position]): rejects
/// a fix whose accuracy is worse than [_maxAccuracyM], or whose implied speed
/// over [seconds]/[meters] since the previous fix exceeds [_maxSpeedMps]. With
/// no previous fix ([meters]/[seconds] null) only accuracy is judged.
bool isPlausibleFix({
  required double accuracyM,
  double? meters,
  double? seconds,
}) {
  if (accuracyM > _maxAccuracyM) {
    return false;
  }
  if (meters == null || seconds == null || seconds <= 0) {
    return true;
  }
  return meters / seconds <= _maxSpeedMps;
}
