import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' show Response;
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

  /// How long a snapshot waits before it goes up. Only enough to coalesce a
  /// burst of taps — a follower is watching this happen live, so anything longer
  /// is felt as the other screen lagging behind.
  static const _activeWorkoutDebounce = Duration(milliseconds: 400);

  /// The `updated` stamp of the account's active workout as this device last saw
  /// it — from its own push or from a pull. The server writes it, so it orders
  /// the devices' writes without trusting any of their clocks. 0 means "no
  /// workout known", which is what a fresh start sends.
  static int _knownUpdate = 0;

  /// Which workout [_knownUpdate] belongs to (its start). A stamp is only ever
  /// valid for its OWN workout: sending it for a different one claims to be
  /// carrying on a workout the sender never saw, and the account rightly refuses
  /// that — silently, for as long as the workout runs, so the phone worked out
  /// alone and the panel never heard a thing. Every workout therefore starts
  /// from 0 unless the account has confirmed THAT one.
  static int _stampedWorkoutStart = 0;
  static final Map<String, Timer> _timers = {};

  /// Collections whose local change has not reached the backend yet — the
  /// debounce is still armed, or its POST is in flight. See [_localWins].
  static final Set<String> _unsent = {};

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
    _unsent.add(key);
    _timers[key] = Timer(delay, () async {
      try {
        await send();
      } finally {
        _unsent.remove(key);
      }
    });
  }

  /// Whether the local copy of [collection] must win over a pull response.
  ///
  /// True while a local change is still on its way up: the server answered
  /// without it, and the pulls REPLACE the local collection, so adopting that
  /// answer silently reverts the user's edit — exactly how a just-confirmed
  /// training disappears again. The push that follows makes the server agree.
  ///
  /// ponytail: one flag, no per-item versions. A response that overtakes a push
  /// which already completed still clobbers, but only on this device and only
  /// until the next pull — the server has the change by then.
  @visibleForTesting
  bool localWins(String collection) => _unsent.contains(collection);

  /// Cancels any armed pushes — for tests, so a mutation's debounce timer does
  /// not outlive the test as a pending timer.
  @visibleForTesting
  static void cancelPending() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _unsent.clear();
    _forgetStamp();
  }

  /// No workout on the account (or none this device has been told about), so the
  /// next push is a fresh start.
  static void _forgetStamp() {
    _knownUpdate = 0;
    _stampedWorkoutStart = 0;
  }

  Future<Response?> _post(String url, Map<String, Object> body) =>
      Request.post(url: url, body: body).send(null);

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
    delay: _activeWorkoutDebounce,
  );

  /// Sends the snapshot together with the stamp of the account copy this device
  /// last saw, so the server can tell a device carrying a workout on from one
  /// starting a fresh one — and refuse the former once the workout has been
  /// ended elsewhere.
  Future<void> _sendActiveWorkout(WorkoutSnapshot snapshot) async {
    final response = await _post('/sport/workout/active/sync/', {
      'workout': snapshot.toJson(),
      'updated': stampFor(snapshot.startedAtMs),
    });
    _rememberUpdate(response, snapshot.startedAtMs);
  }

  /// Whether the account has confirmed a running workout to this device — a pull
  /// that answered with one, or a push it accepted. False the moment the account
  /// says none runs. Read BEFORE a poll to tell a workout ENDED elsewhere from
  /// one of this device's own that never reached the account at all.
  static bool get activeWorkoutConfirmed => _stampedWorkoutStart != 0;

  /// The stamp to send for the workout that started at [startedAtMs]: the one
  /// the account confirmed for THIS workout, or 0 for any other — a workout this
  /// device is starting, not carrying on.
  @visibleForTesting
  static int stampFor(int startedAtMs) =>
      _stampedWorkoutStart == startedAtMs ? _knownUpdate : 0;

  /// Keeps the newest stamp the account answered with. A response without one
  /// (a refused push, a failed request) leaves it alone: the stamp still
  /// describes the copy this device last saw.
  void _rememberUpdate(Response? response, int startedAtMs) {
    if (response == null) {
      return;
    }
    final body = jsonDecode(response.body);
    if (body['success'] != true || body['updated'] is! num) {
      return;
    }
    _knownUpdate = (body['updated'] as num).toInt();
    _stampedWorkoutStart = startedAtMs;
  }

  /// Ends the shared workout. Disarms any pending push first — a snapshot timer
  /// firing after the clear would resurrect the finished workout on every other
  /// device.
  Future<void> clearActiveWorkout() async {
    _timers.remove(_activeWorkoutKey)?.cancel();
    // Cancelling skips the timer's `finally`, so drop the flag by hand.
    _unsent.remove(_activeWorkoutKey);
    _forgetStamp();
    await _post('/sport/workout/active/clear/', {});
  }

  /// The account's running workout, or null when the account could not be asked
  /// — which must NOT be read as "no workout runs", or a single failed poll ends
  /// the workout on this device. A null `snapshot` is the account genuinely
  /// holding none; `foreign` marks one written since this device last pushed or
  /// pulled, i.e. by another device, so it is to be adopted rather than dropped
  /// as this device's own copy coming back.
  Future<({WorkoutSnapshot? snapshot, bool foreign})?> pullActiveWorkout(
    BuildContext? context,
  ) async {
    final response = await Request.get(
      url: '/sport/workout/active/find/',
    ).send(context);
    if (response == null) {
      return null;
    }
    final body = jsonDecode(response.body);
    if (body['success'] != true) {
      return null;
    }
    if (body['workout'] is! Map) {
      _forgetStamp();
      return (snapshot: null, foreign: false);
    }
    final snapshot = WorkoutSnapshot.fromJson(
      (body['workout'] as Map).cast<String, dynamic>(),
    );
    final updated = (body['updated'] as num?)?.toInt() ?? 0;
    final foreign = updated > stampFor(snapshot.startedAtMs);
    _knownUpdate = updated;
    _stampedWorkoutStart = snapshot.startedAtMs;
    return (snapshot: snapshot, foreign: foreign);
  }

  // ---- pull all on sign-in ----

  /// Adopts the account's sport data into the local store (on sign-in and on
  /// every cold start), so a returning device shows its full history. Each
  /// collection is replaced with the server's, which is the source of truth.
  ///
  /// The five fetches run concurrently — they write separate collections, and a
  /// cold start waits on this (see [AccountSync]).
  ///
  /// The running workout is deliberately NOT among them. It has exactly one
  /// owner, [TrainingState.watchActiveWorkout], which pulls it the moment the app
  /// opens or resumes and writes it into the live state as well as the store.
  /// This pull only ever wrote the STORE — and the shared state does not re-read
  /// that key ([TrainingState.reload] skips it on purpose) — so pulling here left
  /// the snapshot sitting in storage where nothing on screen would look at it
  /// until the next cold start, and consumed the `updated` stamp the watcher uses
  /// to recognise it as new. The phone then stayed a whole launch behind the
  /// panel, and the runner only opened on the SECOND start.
  Future<void> pull(BuildContext? context) async {
    await Future.wait([
      _pullMeasurements(context),
      _pullExercises(context),
      _pullRoutines(context),
      _pullWorkouts(context),
      _pullTrainings(context),
    ]);
  }

  /// GETs [url] and returns its [key] list, or null when there is nothing safe to
  /// adopt — an unusable response, or one the server answered without a local
  /// change it hasn't been told about yet ([localWins] on [collection]). Every
  /// caller already skips its overwrite on null, so the guard lives here rather
  /// than in each of them.
  Future<List<dynamic>?> _fetch(
    BuildContext? context,
    String url,
    String key,
    String collection,
  ) async {
    final response = await Request.get(url: url).send(context);
    if (response == null || localWins(collection)) {
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
      'measurements',
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
    final list = await _fetch(
      context,
      '/sport/exercises/find/',
      'exercises',
      'exercises',
    );
    if (list == null) {
      return;
    }
    await _store.saveExercises(_decode(list, SportExercise.fromJson));
  }

  Future<void> _pullRoutines(BuildContext? context) async {
    final list = await _fetch(
      context,
      '/sport/routines/find/',
      'routines',
      'routines',
    );
    if (list == null) {
      return;
    }
    await _store.saveRoutines(_decode(list, SportRoutine.fromJson));
  }

  Future<void> _pullWorkouts(BuildContext? context) async {
    final list = await _fetch(
      context,
      '/sport/workouts/find/',
      'workouts',
      'workouts',
    );
    if (list == null) {
      return;
    }
    await _store.saveSessions(_decode(list, WorkoutSession.fromJson));
  }

  Future<void> _pullTrainings(BuildContext? context) async {
    final list = await _fetch(
      context,
      '/sport/trainings/find/',
      'trainings',
      'trainings',
    );
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
