import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sport_models.dart';

/// Persistenz für den Sport-Bereich: JSON-Blobs in [FlutterSecureStorage], wie
/// `g7/store.dart`. Anders als der G7-Store braucht der Sport-Bereich keinen
/// synchronen Isolate-Cache — die UI lädt einmal in einen [ChangeNotifier] und
/// hält die Daten im Speicher. Generische Listen-Helfer, damit Phase 2
/// (Übungen/Routinen/Sessions) nur Keys + Mapper ergänzt.
class SportStore {
  static const _kWeight = 'sport.weight';
  static const _kExercises = 'sport.exercises';
  static const _kRoutines = 'sport.routines';
  static const _kSessions = 'sport.sessions';
  static const _sessionCap = 500;
  static const _kStride = 'sport.stride_cm';
  static const _kStepsBaselineDate = 'sport.steps_baseline_date';
  static const _kStepsBaselineCounter = 'sport.steps_baseline_counter';

  /// Standard-Schrittlänge in cm (für die Distanzschätzung), bis der Nutzer sie
  /// anpasst — grob ein erwachsener Gang.
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

  Future<void> saveRoutines(List<SportRoutine> routines) =>
      _saveList(_kRoutines, routines.map((routine) => routine.toJson()).toList());

  Future<List<WorkoutSession>> loadSessions() async =>
      (await _loadList(_kSessions)).map(WorkoutSession.fromJson).toList();

  /// Speichert die Sessions, gekappt auf die jüngsten [_sessionCap].
  Future<void> saveSessions(List<WorkoutSession> sessions) {
    final capped = sessions.length > _sessionCap
        ? sessions.sublist(sessions.length - _sessionCap)
        : sessions;
    return _saveList(_kSessions, capped.map((s) => s.toJson()).toList());
  }

  Future<int> loadStrideCm() async =>
      int.tryParse(await _storage.read(key: _kStride) ?? '') ?? defStrideCm;

  Future<void> saveStrideCm(int cm) =>
      _storage.write(key: _kStride, value: '$cm');

  /// Der Mitternachts-Bezugspunkt des kumulativen Schrittzählers: Datum +
  /// Zählerstand, aus denen „Schritte heute" abgeleitet wird.
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
