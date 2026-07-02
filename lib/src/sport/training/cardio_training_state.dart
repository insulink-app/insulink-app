import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../sport_store.dart';
import '../sport_sync.dart';
import 'active_training.dart';
import 'cardio_detector.dart';
import 'cardio_models.dart';

/// Shared state of the endurance trainings: the stored [CardioTraining]s plus
/// the in-progress [ActiveTraining]. Pattern like [SportState]: static [load],
/// mutator persists → [notifyListeners]. The live GPS is recorded by the
/// foreground service into the shared location log; this state owns the
/// start/pause/resume/stop lifecycle and reads the log slice back for the UI.
class CardioTrainingState extends ChangeNotifier {
  final SportStore _store;
  final List<CardioTraining> _trainings;
  ActiveTraining? _active;

  CardioTrainingState(this._store, this._trainings, this._active);

  static Future<CardioTrainingState> load() async {
    const store = SportStore();
    final trainings = await store.loadTrainings()
      ..sort((first, second) => first.startMs.compareTo(second.startMs));
    return CardioTrainingState(store, trainings, await store.loadActiveTraining());
  }

  /// Trainings ascending by start time.
  List<CardioTraining> get trainings => List.unmodifiable(_trainings);

  /// The live training being recorded, or null when none is running.
  ActiveTraining? get activeTraining => _active;

  /// Start recording a new live training; the foreground service picks it up and
  /// records GPS into the location log. `ponytail:` recording therefore depends
  /// on that service running (it does whenever glucose reading is active — the
  /// normal state for this app); if a GPS-only mode without a sensor is ever
  /// needed, start the service on training start too.
  Future<void> startTraining(CardioType type) async {
    _active = ActiveTraining(
      type: type,
      startMs: DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
    await _store.saveActiveTraining(_active!);
    await _seedFirstPoint();
  }

  /// Seed the log with the last-known position so the route has a point right
  /// away, instead of waiting for the service's first fresh GPS sample.
  Future<void> _seedFirstPoint() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) {
        return;
      }
      await _store.appendLocationSample(
        TrackPoint(
          lat: last.latitude,
          lng: last.longitude,
          tMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (_) {
      // Best-effort: no cached position just means the first point arrives with
      // the service's first fix.
    }
  }

  Future<void> pauseTraining() async {
    final active = _active;
    if (active == null || active.isPaused) {
      return;
    }
    _active = active.pause();
    notifyListeners();
    await _store.saveActiveTraining(_active!);
  }

  Future<void> resumeTraining() async {
    final active = _active;
    if (active == null || !active.isPaused) {
      return;
    }
    _active = active.resume();
    notifyListeners();
    await _store.saveActiveTraining(_active!);
  }

  /// Finish the live training: build a [CardioTraining] from the location-log
  /// slice recorded since it started, store it and clear the active state.
  Future<void> stopTraining() async {
    final active = _active;
    if (active == null) {
      return;
    }
    final endMs = DateTime.now().millisecondsSinceEpoch;
    final track = await activeTrack();
    _active = null;
    await _store.clearActiveTraining();
    await addTraining(
      CardioTraining(
        id: active.startMs.toRadixString(36),
        type: active.type,
        startMs: active.startMs,
        endMs: endMs,
        track: track,
        distanceM: _trackDistanceM(track),
      ),
    );
  }

  /// The route recorded so far for the active training (log points since start).
  Future<List<TrackPoint>> activeTrack() async {
    final active = _active;
    if (active == null) {
      return const [];
    }
    final log = await _store.loadLocationLog();
    return [
      for (final point in log)
        if (point.tMs >= active.startMs) point,
    ];
  }

  double _trackDistanceM(List<TrackPoint> track) {
    var total = 0.0;
    for (var index = 1; index < track.length; index++) {
      total += Geolocator.distanceBetween(
        track[index - 1].lat,
        track[index - 1].lng,
        track[index].lat,
        track[index].lng,
      );
    }
    return total;
  }

  Future<void> addTraining(CardioTraining training) async {
    _trainings.add(training);
    notifyListeners();
    await _saveTrainings();
  }

  Future<void> removeTraining(String id) async {
    _trainings.removeWhere((training) => training.id == id);
    notifyListeners();
    await _saveTrainings();
  }

  /// Scans the background GPS log for endurance trainings and saves new ones
  /// directly (marked as auto-detected). Runs over points added since the last
  /// scan (watermark), skips anything overlapping an existing training. Called
  /// on opening the sport tab. `ponytail:` the watermark advances to the newest
  /// point, so a training still in progress at scan time is finalised early;
  /// acceptable for a page-open scan, revisit if live detection is wanted.
  Future<void> detectFromLog() async {
    final log = await _store.loadLocationLog();
    if (log.isEmpty) {
      return;
    }
    final watermark = await _store.loadDetectWatermark();
    final fresh = watermark == null
        ? log
        : [for (final point in log) if (point.tMs > watermark) point];
    await _store.saveDetectWatermark(log.last.tMs);
    var changed = false;
    for (final training in const CardioDetector().detect(fresh)) {
      if (_overlapsExisting(training)) {
        continue;
      }
      _trainings.add(training);
      changed = true;
    }
    if (!changed) {
      return;
    }
    _trainings.sort((first, second) => first.startMs.compareTo(second.startMs));
    notifyListeners();
    await _saveTrainings();
  }

  bool _overlapsExisting(CardioTraining candidate) {
    for (final existing in _trainings) {
      if (candidate.startMs <= existing.endMs &&
          existing.startMs <= candidate.endMs) {
        return true;
      }
    }
    return false;
  }

  /// Persist the trainings and queue a backend sync.
  Future<void> _saveTrainings() async {
    await _store.saveTrainings(_trainings);
    SportSync().pushTrainings();
  }
}
