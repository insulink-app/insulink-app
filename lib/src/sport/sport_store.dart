import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sport_models.dart';
import 'training/cardio_models.dart';

/// Persistence for the sport area: JSON blobs in [FlutterSecureStorage], like
/// `g7/store.dart`. Unlike the G7 store, the sport area needs no synchronous
/// isolate cache — the UI loads once into a [ChangeNotifier] and keeps the data
/// in memory. Generic list helpers so phase 2 (exercises/routines/sessions) only
/// adds keys + mappers.
class SportStore {
  static const _kWeight = 'sport.weight';
  static const _kExercises = 'sport.exercises';
  static const _kRoutines = 'sport.routines';
  static const _kSessions = 'sport.sessions';
  static const _kActivityArchive = 'sport.activity_archive';
  static const _kTrainings = 'sport.trainings';
  static const _kLocationLog = 'sport.location_log';
  static const _sessionCap = 500;
  static const _trainingCap = 500;
  static const _locationLogCap = 2000;
  static const _kStride = 'sport.stride_cm';
  static const _kStepsBaselineDate = 'sport.steps_baseline_date';
  static const _kStepsBaselineCounter = 'sport.steps_baseline_counter';

  /// Default stride length in cm (for the distance estimate), until the user
  /// adjusts it — roughly an adult's stride.
  static const defStrideCm = 75;

  final FlutterSecureStorage _storage;

  const SportStore([this._storage = const FlutterSecureStorage()]);

  Future<List<Map<String, dynamic>>> _loadList(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> _saveList(String key, List<Map<String, dynamic>> list) =>
      _storage.write(key: key, value: jsonEncode(list));

  Future<List<WeightEntry>> loadWeights() async =>
      (await _loadList(_kWeight)).map(WeightEntry.fromJson).toList();

  Future<void> saveWeights(List<WeightEntry> weights) =>
      _saveList(_kWeight, weights.map((entry) => entry.toJson()).toList());

  Future<List<SportExercise>> loadExercises() async =>
      (await _loadList(_kExercises)).map(SportExercise.fromJson).toList();

  Future<void> saveExercises(List<SportExercise> exercises) =>
      _saveList(_kExercises, exercises.map((ex) => ex.toJson()).toList());

  Future<List<SportRoutine>> loadRoutines() async =>
      (await _loadList(_kRoutines)).map(SportRoutine.fromJson).toList();

  Future<void> saveRoutines(List<SportRoutine> routines) => _saveList(
    _kRoutines,
    routines.map((routine) => routine.toJson()).toList(),
  );

  Future<List<WorkoutSession>> loadSessions() async =>
      (await _loadList(_kSessions)).map(WorkoutSession.fromJson).toList();

  /// Saves the sessions, capped to the most recent [_sessionCap].
  Future<void> saveSessions(List<WorkoutSession> sessions) {
    final capped = sessions.length > _sessionCap
        ? sessions.sublist(sessions.length - _sessionCap)
        : sessions;
    return _saveList(_kSessions, capped.map((s) => s.toJson()).toList());
  }

  Future<List<CardioTraining>> loadTrainings() async =>
      (await _loadList(_kTrainings)).map(CardioTraining.fromJson).toList();

  Future<void> saveTrainings(List<CardioTraining> trainings) {
    final capped = trainings.length > _trainingCap
        ? trainings.sublist(trainings.length - _trainingCap)
        : trainings;
    return _saveList(_kTrainings, capped.map((t) => t.toJson()).toList());
  }

  Future<List<DailyActivity>> loadActivityArchive() async =>
      (await _loadList(_kActivityArchive)).map(DailyActivity.fromJson).toList();

  Future<void> saveActivityArchive(List<DailyActivity> days) =>
      _saveList(_kActivityArchive, days.map((day) => day.toJson()).toList());

  /// Rolling background location log (ring buffer, capped to the most recent
  /// [_locationLogCap] points) — filled by the foreground service on a ~60s
  /// cadence, raw material for later location features.
  Future<List<TrackPoint>> loadLocationLog() async =>
      (await _loadList(_kLocationLog)).map(TrackPoint.fromJson).toList();

  Future<void> appendLocationSample(TrackPoint sample) async {
    final log = await loadLocationLog()
      ..add(sample);
    final capped = log.length > _locationLogCap
        ? log.sublist(log.length - _locationLogCap)
        : log;
    await _saveList(
      _kLocationLog,
      capped.map((point) => point.toJson()).toList(),
    );
  }

  Future<int> loadStrideCm() async =>
      int.tryParse(await _storage.read(key: _kStride) ?? '') ?? defStrideCm;

  Future<void> saveStrideCm(int cm) =>
      _storage.write(key: _kStride, value: '$cm');

  /// The midnight reference point of the cumulative step counter: date +
  /// counter, from which "steps today" is derived.
  Future<({String date, int counter})?> loadStepsBaseline() async {
    final date = await _storage.read(key: _kStepsBaselineDate);
    final counter = int.tryParse(
      await _storage.read(key: _kStepsBaselineCounter) ?? '',
    );
    if (date == null || counter == null) {
      return null;
    }
    return (date: date, counter: counter);
  }

  Future<void> saveStepsBaseline(String date, int counter) async {
    await _storage.write(key: _kStepsBaselineDate, value: date);
    await _storage.write(key: _kStepsBaselineCounter, value: '$counter');
  }
}
