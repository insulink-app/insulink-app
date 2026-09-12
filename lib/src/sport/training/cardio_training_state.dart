import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../sport_store.dart';
import '../sport_sync.dart';
import 'active_training.dart';
import 'cardio_models.dart';

/// Shared state of the endurance trainings: the stored [CardioTraining]s plus
/// the in-progress [ActiveTraining]. Pattern like [SportState]: static [load],
/// mutator persists → [notifyListeners]. The live GPS is recorded by the
/// foreground service into the shared location log; this state owns the
/// start/pause/resume/stop lifecycle and reads the log slice back for the UI.
class CardioTrainingState extends ChangeNotifier {
  final SportStore _store;
  final List<CardioTraining> _trainings;
  List<CardioTraining> _pending;
  ActiveTraining? _active;

  CardioTrainingState(
    this._store,
    this._trainings,
    this._pending,
    this._active,
  );

  static Future<CardioTrainingState> load() async {
    const store = SportStore();
    final trainings = await store.loadTrainings()
      ..sort((first, second) => first.startMs.compareTo(second.startMs));
    return CardioTrainingState(
      store,
      trainings,
      await store.loadPendingTrainings(),
      await store.loadActiveTraining(),
    );
  }

  /// Trainings ascending by start time.
  List<CardioTraining> get trainings => List.unmodifiable(_trainings);

  /// Auto-detected trainings awaiting the user's confirm/reject (newest first).
  List<CardioTraining> get pendingTrainings =>
      List.unmodifiable(_pending.reversed);

  /// The training with [id], confirmed or still pending, or null when neither
  /// list holds it any more (rejected, or deleted on another device).
  CardioTraining? trainingById(String id) {
    for (final training in [..._trainings, ..._pending]) {
      if (training.id == id) {
        return training;
      }
    }
    return null;
  }

  /// Whether [id] is a detection still awaiting the user's decision.
  bool isPending(String id) => _pending.any((training) => training.id == id);

  /// Confirm a pending detection → it becomes a normal training (and syncs).
  Future<void> confirmDetected(String id) async {
    final index = _pending.indexWhere((training) => training.id == id);
    if (index < 0) {
      return;
    }
    final confirmed = _pending.removeAt(index);
    _trainings
      ..add(confirmed)
      ..sort((first, second) => first.startMs.compareTo(second.startMs));
    notifyListeners();
    await _store.confirmPendingTraining(id);
    SportSync().pushTrainings();
  }

  /// Reject (discard) a pending detection.
  Future<void> rejectDetected(String id) async {
    _pending.removeWhere((training) => training.id == id);
    notifyListeners();
    await _store.rejectPendingTraining(id);
  }

  /// Re-read the pending detections + confirmed trainings the background service
  /// (or a notification action) may have written — the store is cross-isolate,
  /// so the UI must reload to see writes from the service isolate.
  Future<void> reloadPending() async {
    // Drain any Confirm/Reject taps buffered by the notification-action isolate
    // right now (this isolate has secure storage + dart:io), so a decision takes
    // effect the moment the user opens the tab — not only on the service's next
    // 30 s watchdog tick.
    final confirmed = await _store.applyTrainingDecisions();
    _pending = await _store.loadPendingTrainings();
    final trainings = await _store.loadTrainings()
      ..sort((first, second) => first.startMs.compareTo(second.startMs));
    _trainings
      ..clear()
      ..addAll(trainings);
    notifyListeners();
    // A notification-confirmed training only exists locally until this fires —
    // the next pull would replace it with the account's list, which never saw it.
    if (confirmed) {
      SportSync().pushTrainings();
    }
  }

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

  /// Change the type (walk/jog/bike) of an existing training after the fact.
  Future<void> changeTrainingType(String id, CardioType type) async {
    final index = _trainings.indexWhere((training) => training.id == id);
    if (index < 0) {
      return;
    }
    _trainings[index] = _trainings[index].withType(type);
    notifyListeners();
    await _saveTrainings();
  }

  Future<void> removeTraining(String id) async {
    _trainings.removeWhere((training) => training.id == id);
    notifyListeners();
    await _saveTrainings();
  }

  /// Persist the trainings and queue a backend sync.
  Future<void> _saveTrainings() async {
    await _store.saveTrainings(_trainings);
    SportSync().pushTrainings();
  }
}
