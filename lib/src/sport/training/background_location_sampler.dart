import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../sport_store.dart';
import 'active_training.dart';
import 'cardio_models.dart';
import 'location_sync.dart';

/// Which cadence the open GPS stream is running at. A tier change reopens the
/// stream with the matching settings; the pure [gpsTierFor] picks it.
enum GpsTier { detect, activeDetect, recording }

/// Periodically samples the position in the foreground-service isolate and
/// appends it to the location log ([SportStore.appendLocationSample]) — the raw
/// material for the cardio auto-detection AND the live route of a manually
/// started training (which records via this same log while backgrounded).
///
/// The cadence is **adaptive**: whenever a training records OR — for
/// auto-detection — we're recently moving, we open a continuous
/// [Geolocator.getPositionStream] (dense route, GPS radio kept hot). Only truly
/// at rest do we fall back to a sparse one-shot poll (~55s) to save battery and
/// to notice movement starting. A running training streams every
/// [_recordingInterval]; auto-detection every the sparser [_detectInterval]; a
/// paused training records nothing — but both streams are high accuracy, see
/// [_streamSettings]. Fixes are passed through an outlier filter ([isPlausibleFix])
/// so a poor-accuracy or teleport-jump glitch never lands in the route. Only runs
/// when location is permitted (otherwise silently does nothing); glucose reading
/// never depends on it.
///
/// **Why a stream, not short one-shot polls** (the fix for the multi-minute
/// gaps): a one-shot [Geolocator.getCurrentPosition] lets Android power the GPS
/// radio down between ticks, so every tick cold-reacquires a fix — routinely
/// slower than [_fixTimeout], producing minutes with no points. A stream keeps
/// the radio on and delivers steady fixes, which is why denser auto-detect
/// tracking uses it too (not a faster poll). The stream's cadence is set on the
/// PLATFORM ([AndroidSettings.intervalDuration] + `distanceFilter`), not
/// throttled in Dart: only the platform request actually duty-cycles the GNSS
/// radio, and the distance filter means standing still costs nothing at all.
/// The backend send cadence is decoupled from this: [LocationSync] batches the
/// queued fixes and flushes them roughly once a minute, so dense sampling
/// doesn't mean dense network I/O.
///
/// The GPS radio therefore stays hot only while moving (plus a short
/// [_movingLinger] so a red light doesn't drop it) — at rest it's the sparse poll.
///
/// The battery saver ([_isDetectionPaused]) switches all of that off except a
/// recording training's route: see the guard at the top of [tick].
class BackgroundLocationSampler {
  final SportStore _store;
  final void Function(String) _onLog;
  DateTime? _lastSampledAt;
  DateTime? _lastMovingAt;

  /// When the current uninterrupted moving streak began (null when at rest).
  /// Once it is older than [_sustainedMovingAfter] the movement looks like a
  /// real training, so detection tracking ramps up to [GpsTier.activeDetect].
  DateTime? _movingSince;
  Position? _lastFix;
  StreamSubscription<Position>? _stream;

  /// The cadence the open [_stream] is running at — a tier flip has to reopen it
  /// with the other settings.
  GpsTier? _streamTier;

  static const _idleInterval = Duration(seconds: 55);
  static const _recordingInterval = Duration(seconds: 4);

  /// Auto-detect cadence while moving without a training. Detection itself would
  /// tolerate minutes ([CardioDetector._maxGap] is 5), but a detected training's
  /// route, distance and km-splits are built from these same points — at 30s a
  /// 25 km/h ride jumps ~200 m per point and cuts every corner. So the cadence
  /// is set by the route we want to keep, not by the detector.
  static const _detectInterval = Duration(seconds: 10);

  /// Denser detect cadence once movement has been sustained ([_movingSince]
  /// older than [_sustainedMovingAfter]) — an auto-detected training then gets a
  /// route almost as dense as a manually recorded one, without paying that cost
  /// for a brief walk-to-the-car. Still coarser than [_recordingInterval] to
  /// stay easy on the battery.
  static const _activeDetectInterval = Duration(seconds: 5);

  /// How long movement must persist before the detect stream ramps up to
  /// [_activeDetectInterval]. Long enough that a short errand never triggers the
  /// denser cadence; short enough to catch most of a training's route.
  static const _sustainedMovingAfter = Duration(minutes: 3);
  static const _fixTimeout = Duration(seconds: 20);

  /// How long after the last moving fix we keep the stream open, so a brief stop
  /// (traffic light, crossing) doesn't tear the GPS radio down and re-gap.
  static const _movingLinger = Duration(seconds: 90);

  /// At or above this speed (km/h) a fix counts as "moving" → keep streaming.
  static const _movingKmh = 3.0;

  /// Reports whether the OS activity recognition currently says "still". While
  /// it does, the idle one-shot GPS poll is skipped entirely: the recognition
  /// stream is hardware-batched and near-free, and it flips off "still" before
  /// the next tick, so movement is still noticed promptly — without a GPS fix
  /// every [_idleInterval] around the clock. Defaults to never-still (poll as
  /// before) when no recognizer is wired up or permitted.
  final bool Function() _isStill;

  /// Reports whether the battery saver has paused the cardio auto-detection (see
  /// `BatteryMode.pausesDetection`). While it does, this sampler does nothing
  /// unless a training is actually recording — which is the whole saving: no
  /// detect stream, no idle poll, and so no location POSTs either. Defaults to
  /// never-paused. Read through a callback (not loaded here) so the 10 s tick
  /// gains no secure-storage read; the service isolate caches the mode.
  final bool Function() _isDetectionPaused;

  BackgroundLocationSampler({
    this._store = const SportStore(),
    void Function(String)? onLog,
    this._isStill = _neverStill,
    this._isDetectionPaused = _neverPaused,
  }) : _onLog = (onLog ?? _noLog);

  static void _noLog(String _) {}

  static bool _neverStill() => false;

  static bool _neverPaused() => false;

  /// Called by the service timer; keeps the stream open while a training records
  /// or we're recently moving (auto-detection), otherwise one-shot polls at the
  /// idle interval to notice movement starting.
  Future<void> tick() async {
    try {
      final active = await _store.loadActiveTraining();
      if (!_recentlyMoving) {
        _movingSince = null;
      }
      final recording = active != null && !active.isPaused;
      // The saver pauses DETECTION, never a recording. A manually started
      // training keeps its dense route; everything else stands down here, which
      // is the single gate that covers both the detect stream and the idle poll.
      if (!recording && _isDetectionPaused()) {
        await _syncStream(null);
        return;
      }
      // Stream while recording, or — with no active training — while recently
      // moving (dense auto-detect route), ramping to the denser tier once the
      // movement has been sustained. A paused training (active, not recording)
      // must record nothing, so it never streams.
      final tier = _wantedTier(active, recording);
      await _syncStream(tier);
      if (active != null || _stream != null) {
        return;
      }
      final last = _lastSampledAt;
      if (last != null && DateTime.now().difference(last) < _idleInterval) {
        return;
      }
      if (_isStill()) {
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

  /// The cadence tier the current state wants, or null to keep no stream open:
  /// a recording training gets [GpsTier.recording]; with no training, sustained
  /// movement gets the denser [GpsTier.activeDetect] and briefer movement the
  /// sparse [GpsTier.detect]; at rest, none.
  GpsTier? _wantedTier(ActiveTraining? active, bool recording) {
    return gpsTierFor(
      recording: recording,
      hasActiveTraining: active != null,
      recentlyMoving: _recentlyMoving,
      sustainedMoving: _sustainedMoving,
    );
  }

  /// Opens the stream when a tier is wanted, closes it at rest, and reopens it
  /// when the tier (and so the cadence) flips. Idempotent per state.
  Future<void> _syncStream(GpsTier? tier) async {
    if (_stream != null && tier != _streamTier) {
      await _stopStream();
    }
    if (tier != null && _stream == null) {
      await _startStream(tier);
    }
  }

  Future<void> _startStream(GpsTier tier) async {
    if (!await _ready()) {
      return;
    }
    _streamTier = tier;
    _stream = Geolocator.getPositionStream(
      locationSettings: _streamSettings(tier),
    ).listen(
      _onStreamFix,
      onError: (Object error) => _onLog('location stream error: $error'),
    );
    _onLog('location: ${tier.name} stream started');
  }

  /// The platform request that decides the actual battery cost. Every tier asks
  /// for high accuracy and saves power through the CADENCE instead: the interval
  /// plus the distance filter are what let the radio duty-cycle, and standing
  /// still costs nothing at all (no movement, no fixes, no radio).
  ///
  /// **Auto-detection must not drop to [LocationAccuracy.medium]** — that is
  /// `PRIORITY_BALANCED_POWER_ACCURACY` (~100 m), and [isPlausibleFix] rejects
  /// anything worse than [_maxAccuracyM] (50 m). The cheaper provider would have
  /// its fixes filtered straight back out of the route, leaving the detector
  /// with no segments.
  LocationSettings _streamSettings(GpsTier tier) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: switch (tier) {
        GpsTier.recording => 5,
        GpsTier.activeDetect => 8,
        GpsTier.detect => 15,
      },
      intervalDuration: switch (tier) {
        GpsTier.recording => _recordingInterval,
        GpsTier.activeDetect => _activeDetectInterval,
        GpsTier.detect => _detectInterval,
      },
    );
  }

  Future<void> _stopStream() async {
    await _stream?.cancel();
    _stream = null;
    _streamTier = null;
    _onLog('location: stream stopped');
  }

  void _onStreamFix(Position fix) {
    final now = DateTime.now();
    _lastSampledAt = now;
    unawaited(_record(fix, now.millisecondsSinceEpoch));
  }

  /// Queues every fix for the backend (even a coarse one — a 100 m city fix is
  /// fine for a position log), then appends to the local route only if it passes
  /// the strict cardio outlier filter.
  Future<void> _record(Position fix, int tMs) async {
    if (fix.speed * 3.6 >= _movingKmh) {
      _lastMovingAt = DateTime.now();
      _movingSince ??= DateTime.now();
    }
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
    final seconds =
        fix.timestamp.difference(prev.timestamp).inMilliseconds /
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

  /// Whether a moving fix landed within the last [_movingLinger] — keeps the
  /// stream open across brief stops instead of dropping and re-acquiring it.
  bool get _recentlyMoving {
    final movingAt = _lastMovingAt;
    return movingAt != null &&
        DateTime.now().difference(movingAt) < _movingLinger;
  }

  /// Whether the current moving streak has lasted long enough to look like a
  /// training rather than a brief errand — the trigger for the denser detect
  /// cadence.
  bool get _sustainedMoving {
    final since = _movingSince;
    return since != null &&
        DateTime.now().difference(since) >= _sustainedMovingAfter;
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
/// Pure cadence picker (extracted so the tier logic is testable without time or
/// storage): a recording training gets [GpsTier.recording]; with no training,
/// recent movement gets the sparse [GpsTier.detect] or — once movement has been
/// [sustainedMoving] — the denser [GpsTier.activeDetect]; otherwise null (no
/// stream). A paused training ([hasActiveTraining] without [recording]) records
/// nothing, so it streams nothing.
GpsTier? gpsTierFor({
  required bool recording,
  required bool hasActiveTraining,
  required bool recentlyMoving,
  required bool sustainedMoving,
}) {
  if (recording) {
    return GpsTier.recording;
  }
  if (!hasActiveTraining && recentlyMoving) {
    return sustainedMoving ? GpsTier.activeDetect : GpsTier.detect;
  }
  return null;
}

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
