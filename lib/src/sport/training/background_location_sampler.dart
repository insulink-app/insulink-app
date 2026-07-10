import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../sport_store.dart';
import 'cardio_models.dart';
import 'location_sync.dart';

/// Periodically samples the position in the foreground-service isolate and
/// appends it to the location log ([SportStore.appendLocationSample]) — the raw
/// material for the cardio auto-detection AND the live route of a manually
/// started training (which records via this same log while backgrounded).
///
/// The cadence is **adaptive**: while recording a training we open a continuous
/// [Geolocator.getPositionStream] (dense route, GPS radio kept hot); while
/// merely moving or at rest we one-shot poll (~10s / ~55s) to save battery. A
/// running training forces high accuracy; a paused training records nothing.
/// Fixes are passed through an outlier filter ([isPlausibleFix]) so a
/// poor-accuracy or teleport-jump glitch never lands in the route. Only runs
/// when location is permitted (otherwise silently does nothing); glucose reading
/// never depends on it.
///
/// **Why a stream while recording** (the fix for the multi-minute gaps): a
/// one-shot [Geolocator.getCurrentPosition] lets Android power the GPS radio
/// down between the 4s ticks, so every tick cold-reacquires a fix — routinely
/// slower than [_fixTimeout], producing minutes with no points. A stream keeps
/// the radio on and delivers steady fixes.
class BackgroundLocationSampler {
  final SportStore _store;
  final void Function(String) _onLog;
  DateTime? _lastSampledAt;
  Position? _lastFix;
  StreamSubscription<Position>? _stream;

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

  /// Called by the service timer; opens/closes the recording stream and, when
  /// not recording, one-shot polls at the adaptive interval.
  Future<void> tick() async {
    try {
      final active = await _store.loadActiveTraining();
      final recording = active != null && !active.isPaused;
      await _syncStream(recording);
      if (recording || active != null) {
        return;
      }
      final last = _lastSampledAt;
      if (last != null &&
          DateTime.now().difference(last) < _interval) {
        return;
      }
      _lastSampledAt = DateTime.now();
      if (!await _ready()) {
        return;
      }
      final fix = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(_fixTimeout);
      await _record(fix, DateTime.now().millisecondsSinceEpoch);
    } catch (error) {
      // ponytail: best-effort; a failed/timed-out fix just skips this tick and
      // retries on the next one — but log it, so "no report at all" is never
      // silent (a throwing loadActiveTraining/getCurrentPosition used to kill
      // every tick with no trace).
      _onLog('location sample error: $error');
    }
  }

  /// Opens the high-accuracy recording stream when a training starts, closes it
  /// when it stops/pauses. Idempotent per state.
  Future<void> _syncStream(bool recording) async {
    if (recording && _stream == null) {
      await _startStream();
    } else if (!recording && _stream != null) {
      await _stopStream();
    }
  }

  Future<void> _startStream() async {
    if (!await _ready()) {
      return;
    }
    _stream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen(
      _onStreamFix,
      onError: (Object error) => _onLog('location stream error: $error'),
    );
    _onLog('location: recording stream started');
  }

  Future<void> _stopStream() async {
    await _stream?.cancel();
    _stream = null;
    _onLog('location: recording stream stopped');
  }

  /// Throttles the stream (which can deliver faster than we need) to at most one
  /// recorded point per [_recordingInterval].
  void _onStreamFix(Position fix) {
    final now = DateTime.now();
    final last = _lastSampledAt;
    if (last != null && now.difference(last) < _recordingInterval) {
      return;
    }
    _lastSampledAt = now;
    unawaited(_record(fix, now.millisecondsSinceEpoch));
  }

  /// Queues every fix for the backend (even a coarse one — a 100 m city fix is
  /// fine for a position log), then appends to the local route only if it passes
  /// the strict cardio outlier filter.
  Future<void> _record(Position fix, int tMs) async {
    LocationSync().queue(fix.latitude, fix.longitude, tMs, _onLog);
    if (!_accept(fix)) {
      return;
    }
    _lastFix = fix;
    await _store.appendLocationSample(
      TrackPoint(lat: fix.latitude, lng: fix.longitude, tMs: tMs),
    );
  }

  /// Location permitted AND device location services on.
  Future<bool> _ready() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _onLog('location: permission not granted ($permission)');
      return false;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      _onLog('location: device location services disabled');
      return false;
    }
    return true;
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

  /// Medium cadence while moving; slow at rest. (Recording uses the stream, not
  /// this interval.)
  Duration get _interval => _isMoving ? _movingInterval : _idleInterval;

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
