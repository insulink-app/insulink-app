import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_store.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';

/// Mirrors the user's sport data to their backend account and pulls it back on
/// sign-in. Split by domain, one endpoint pair per collection (like the glucose
/// sync): measurements (steps/distance/calories/weight), exercise + routine
/// templates, completed workouts (logbook) and cardio trainings.
///
/// Each `push*` debounces a best-effort replace-all of that one collection
/// (null context, like the glucose/event sync); [pull] runs in the UI isolate on
/// sign-in and writes the account's data into the store before the provider tree
/// reloads. ponytail: replace-all (the app always sends the full current list)
/// keeps deletes/edits/reorders correct without per-item endpoints.
class SportSync {
  static const _store = SportStore();
  static const _activeWorkoutKey = 'active-workout';
  static final Map<String, Timer> _timers = {};

  // ---- push (debounced per collection) ----

  void pushMeasurements() => _debounce('measurements', _sendMeasurements);
  void pushExercises() => _debounce('exercises', _sendExercises);
  void pushRoutines() => _debounce('routines', _sendRoutines);
  void pushWorkouts() => _debounce('workouts', _sendWorkouts);
  void pushTrainings() => _debounce('trainings', _sendTrainings);

  void _debounce(
    String key,
    Future<void> Function() send, {
    Duration delay = const Duration(seconds: 3),
  }) {
    _timers[key]?.cancel();
    _timers[key] = Timer(delay, send);
  }

  /// Cancels any armed pushes — for tests, so a mutation's debounce timer does
  /// not outlive the test as a pending timer.
  @visibleForTesting
  static void cancelPending() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  Future<void> _post(String url, Map<String, Object> body) async {
    await Request.post(url: url, body: body).send(null);
  }

  /// Weight plus the daily activity metrics, each as a typed value+time entry.
  Future<void> _sendMeasurements() async {
    final weights = await _store.loadWeights();
    final activity = await _store.loadActivityArchive();
    final entries = <Map<String, Object>>[
      for (final weight in weights)
        {'type': 'WEIGHT', 'value': weight.kg, 'time': weight.atEpochMs},
      for (final day in activity) ...[
        {'type': 'STEPS', 'value': day.steps, 'time': _dayMs(day.dateKey)},
        {
          'type': 'DISTANCE',
          'value': day.distanceKm,
          'time': _dayMs(day.dateKey),
        },
        {
          'type': 'CALORIES',
          'value': day.calories,
          'time': _dayMs(day.dateKey),
        },
      ],
    ];
    await _post('/sport/measurements/sync/', {'entries': entries});
  }

  /// Deletes a single weight from the account via the measurements delete
  /// endpoint. Needed because the measurements `sync` MERGES (never deletes), so
  /// a removed point only vanishes server-side when named here by its natural key
  /// (type + timestamp). The endpoint takes an `entries` list, like `sync`.
  Future<void> deleteWeight(WeightEntry entry) async {
    await _post('/sport/measurements/delete/', {
      'entries': [
        {'type': 'WEIGHT', 'time': entry.atEpochMs},
      ],
    });
  }

  Future<void> _sendExercises() async {
    final exercises = await _store.loadExercises();
    await _post('/sport/exercises/sync/', {
      'exercises': exercises.map((exercise) => exercise.toJson()).toList(),
    });
  }

  Future<void> _sendRoutines() async {
    final routines = await _store.loadRoutines();
    await _post('/sport/routines/sync/', {
      'routines': routines.map((routine) => routine.toJson()).toList(),
    });
  }

  Future<void> _sendWorkouts() async {
    final sessions = await _store.loadSessions();
    await _post('/sport/workouts/sync/', {
      'workouts': sessions.map((session) => session.toJson()).toList(),
    });
  }

  Future<void> _sendTrainings() async {
    final trainings = await _store.loadTrainings();
    await _post('/sport/trainings/sync/', {
      'trainings': trainings.map((training) => training.toJson()).toList(),
    });
  }

  // ---- active workout (the running workout, shared across devices) ----

  /// Mirrors the running workout's snapshot to the account so another device can
  /// take it over mid-set — the web panel follows a workout started here by
  /// polling this, and the app resumes one started there. Debounced tighter than
  /// the collection pushes: a follower showing the set before last is confusing,
  /// and a snapshot is small.
  void pushActiveWorkout(WorkoutSnapshot snapshot) => _debounce(
    _activeWorkoutKey,
    () => _sendActiveWorkout(snapshot),
    delay: const Duration(seconds: 1),
  );

  Future<void> _sendActiveWorkout(WorkoutSnapshot snapshot) =>
      _post('/sport/workout/active/sync/', {'workout': snapshot.toJson()});

  /// Ends the shared workout. Disarms any pending push first — a snapshot timer
  /// firing after the clear would resurrect the finished workout on every other
  /// device.
  Future<void> clearActiveWorkout() async {
    _timers.remove(_activeWorkoutKey)?.cancel();
    await _post('/sport/workout/active/clear/', {});
  }

  /// The account's running workout, or null when none is running (also null when
  /// the request fails, so a sign-in offline simply resumes nothing).
  Future<WorkoutSnapshot?> pullActiveWorkout(BuildContext? context) async {
    final response = await Request.get(
      url: '/sport/workout/active/find/',
    ).send(context);
    if (response == null) {
      return null;
    }
    final body = jsonDecode(response.body);
    if (body['success'] != true || body['workout'] is! Map) {
      return null;
    }
    return WorkoutSnapshot.fromJson(
      (body['workout'] as Map).cast<String, dynamic>(),
    );
  }

  // ---- pull all on sign-in ----

  /// Adopts the account's sport data into the local store (on sign-in and on
  /// every cold start), so a returning device shows its full history. Each
  /// collection is replaced with the server's, which is the source of truth.
  ///
  /// The six fetches run concurrently — they write separate collections, and a
  /// cold start waits on this (see [AccountSync]).
  Future<void> pull(BuildContext? context) async {
    await Future.wait([
      _pullMeasurements(context),
      _pullExercises(context),
      _pullRoutines(context),
      _pullWorkouts(context),
      _pullTrainings(context),
      _pullActiveWorkout(context),
    ]);
  }

  /// Adopts the account's running workout into the store, so a routine started
  /// on another device (or in the web panel) is offered for resume here. Runs
  /// before the provider tree reloads, like the collection pulls.
  Future<void> _pullActiveWorkout(BuildContext? context) async {
    final snapshot = await pullActiveWorkout(context);
    if (snapshot == null) {
      await _store.clearActiveWorkout();
      return;
    }
    await _store.saveActiveWorkout(snapshot);
  }

  Future<List<dynamic>?> _fetch(
    BuildContext? context,
    String url,
    String key,
  ) async {
    final response = await Request.get(url: url).send(context);
    if (response == null) {
      return null;
    }
    final body = jsonDecode(response.body);
    if (body['success'] != true || body[key] is! List) {
      return null;
    }
    return body[key] as List<dynamic>;
  }

  Future<void> _pullMeasurements(BuildContext? context) async {
    final entries = await _fetch(
      context,
      '/sport/measurements/find/',
      'entries',
    );
    if (entries == null) {
      return;
    }
    final weights = <WeightEntry>[];
    final steps = <String, int>{};
    final distance = <String, double>{};
    final calories = <String, double>{};
    for (final entry in entries.cast<Map<String, dynamic>>()) {
      final value = (entry['value'] as num).toDouble();
      final time = (entry['time'] as num).toInt();
      switch (entry['type']) {
        case 'WEIGHT':
          weights.add(WeightEntry(atEpochMs: time, kg: value));
        case 'STEPS':
          steps[_dateKey(time)] = value.round();
        case 'DISTANCE':
          distance[_dateKey(time)] = value;
        case 'CALORIES':
          calories[_dateKey(time)] = value;
      }
    }
    await _store.saveWeights(weights);
    await _store.saveActivityArchive(_activityDays(steps, distance, calories));
  }

  List<DailyActivity> _activityDays(
    Map<String, int> steps,
    Map<String, double> distance,
    Map<String, double> calories,
  ) {
    final days = {...steps.keys, ...distance.keys, ...calories.keys}.toList()
      ..sort();
    return [
      for (final day in days)
        if ((steps[day] ?? 0) > 0 ||
            (distance[day] ?? 0) > 0 ||
            (calories[day] ?? 0) > 0)
          DailyActivity(
            dateKey: day,
            steps: steps[day] ?? 0,
            distanceKm: distance[day] ?? 0,
            calories: calories[day] ?? 0,
          ),
    ];
  }

  Future<void> _pullExercises(BuildContext? context) async {
    final list = await _fetch(context, '/sport/exercises/find/', 'exercises');
    if (list == null) {
      return;
    }
    await _store.saveExercises(_decode(list, SportExercise.fromJson));
  }

  Future<void> _pullRoutines(BuildContext? context) async {
    final list = await _fetch(context, '/sport/routines/find/', 'routines');
    if (list == null) {
      return;
    }
    await _store.saveRoutines(_decode(list, SportRoutine.fromJson));
  }

  Future<void> _pullWorkouts(BuildContext? context) async {
    final list = await _fetch(context, '/sport/workouts/find/', 'workouts');
    if (list == null) {
      return;
    }
    await _store.saveSessions(_decode(list, WorkoutSession.fromJson));
  }

  Future<void> _pullTrainings(BuildContext? context) async {
    final list = await _fetch(context, '/sport/trainings/find/', 'trainings');
    if (list == null) {
      return;
    }
    await _store.saveTrainings(_decode(list, CardioTraining.fromJson));
  }

  List<T> _decode<T>(
    List<dynamic> list,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    return [for (final item in list) fromJson((item as Map).cast())];
  }

  int _dayMs(String dateKey) => DateTime.parse(dateKey).millisecondsSinceEpoch;

  String _dateKey(int time) {
    final date = DateTime.fromMillisecondsSinceEpoch(time);
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
