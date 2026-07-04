import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../sport_models.dart';
import '../sport_store.dart';
import '../sport_sync.dart';
import 'step_baseline.dart';

/// Reads today's steps from the hardware step counter (`pedometer`). Its own
/// [ChangeNotifier] because the stream lifecycle differs from the CRUD state.
/// Distance/calories are NOT computed here (they're estimates from steps +
/// stride + weight) — see `activity_summary_card.dart`.
class SportActivityState extends ChangeNotifier {
  final SportStore _store;
  StreamSubscription<StepCount>? _subscription;
  StepBaseline? _baseline;
  int? _todaySteps;
  bool _denied = false;
  int? _importedSteps;
  double? _importedDistanceKm;
  double? _importedCalories;
  List<DailyActivity> _archive = const [];

  SportActivityState([this._store = const SportStore()]) {
    _loadArchive();
  }

  Future<void> _loadArchive() async {
    _archive = await _store.loadActivityArchive()
      ..sort((first, second) => first.dateKey.compareTo(second.dateKey));
    notifyListeners();
  }

  /// Daily activity archive (ascending by date) for the detail pages.
  List<DailyActivity> get activityArchive => List.unmodifiable(_archive);

  /// The archive with today's entry patched to the live values — pedometer steps
  /// (the larger of live vs. synced) and any freshly imported distance/calories —
  /// so the detail pages show today up-to-the-minute instead of only the last
  /// Health sync. A synthetic today entry is injected when there is live data but
  /// no archived one yet.
  List<DailyActivity> get activityArchiveWithToday {
    final todayKey = _paddedTodayKey();
    final patched = [
      for (final day in _archive)
        if (day.dateKey == todayKey) _patchToday(day) else day,
    ];
    final hasToday = patched.any((day) => day.dateKey == todayKey);
    if (!hasToday && _hasLiveToday) {
      patched.add(
        _patchToday(
          DailyActivity(
            dateKey: todayKey,
            steps: 0,
            distanceKm: 0,
            calories: 0,
          ),
        ),
      );
    }
    return List.unmodifiable(patched);
  }

  bool get _hasLiveToday =>
      todaySteps > 0 ||
      _importedDistanceKm != null ||
      _importedCalories != null;

  DailyActivity _patchToday(DailyActivity day) => DailyActivity(
    dateKey: day.dateKey,
    steps: todaySteps > day.steps ? todaySteps : day.steps,
    distanceKm: importedDistanceKm ?? day.distanceKm,
    calories: importedCalories ?? day.calories,
  );

  /// Upsert imported days (by [DailyActivity.dateKey]) and persist.
  Future<void> mergeArchive(List<DailyActivity> days) async {
    final byDate = {for (final day in _archive) day.dateKey: day};
    for (final day in days) {
      byDate[day.dateKey] = day;
    }
    // Drop empty days (no steps/distance/calories): they carry no information and
    // otherwise pile up into a huge backend sync. Also cleans any zero-days a
    // previous import already stored.
    _archive = byDate.values.where(_hasActivity).toList()
      ..sort((first, second) => first.dateKey.compareTo(second.dateKey));
    notifyListeners();
    await _store.saveActivityArchive(_archive);
    SportSync().pushMeasurements();
  }

  bool _hasActivity(DailyActivity day) =>
      day.steps > 0 || day.distanceKm > 0 || day.calories > 0;

  /// Today's archive entry (from the last Health sync), if present. Serves as a
  /// **persistent** fallback so synced values don't disappear after a
  /// restart/provider rebuild (the `_imported*` fields are session-only).
  DailyActivity? get _todayArchive {
    final key = _paddedTodayKey();
    for (final day in _archive) {
      if (day.dateKey == key) {
        return day;
      }
    }
    return null;
  }

  /// Today's steps: freshly imported > the larger of pedometer or synced archive
  /// (so the step counter keeps counting live without losing the last synced
  /// value).
  int get todaySteps {
    if (_importedSteps != null) {
      return _importedSteps!;
    }
    final pedometer = _todaySteps ?? 0;
    final archived = _todayArchive?.steps ?? 0;
    return pedometer > archived ? pedometer : archived;
  }

  /// Real values from Google Health: freshly imported or the persistent today
  /// archive value — otherwise null (then the tile estimates from steps + stride
  /// or weight). A non-positive archived value counts as ABSENT: today's steps
  /// are backed up to the archive (see [flushToday]) with distance/calories left
  /// at 0 for a pedometer-only day, and those must still fall back to the
  /// estimate rather than showing a hard 0.
  double? get importedDistanceKm {
    final imported = _importedDistanceKm;
    if (imported != null) {
      return imported;
    }
    final archived = _todayArchive?.distanceKm;
    return (archived != null && archived > 0) ? archived : null;
  }

  double? get importedCalories {
    final imported = _importedCalories;
    if (imported != null) {
      return imported;
    }
    final archived = _todayArchive?.calories;
    return (archived != null && archived > 0) ? archived : null;
  }

  bool get permissionDenied => _denied;

  /// Apply today's values from Google Health (session-only, not persisted).
  void setImported({int? steps, double? distanceKm, double? calories}) {
    _importedSteps = steps;
    _importedDistanceKm = distanceKm;
    _importedCalories = calories;
    notifyListeners();
  }

  /// Requests ACTIVITY_RECOGNITION (if needed) and subscribes to the step
  /// counter. Idempotent — called on first opening the Sport tab, not at app
  /// start (the onboarding step requests the permission).
  Future<void> ensureStarted() async {
    if (_subscription != null) {
      return;
    }
    if (!await Permission.activityRecognition.request().isGranted) {
      _denied = true;
      notifyListeners();
      return;
    }
    await _startStream();
  }

  /// Starts the step stream only if the permission is ALREADY granted, WITHOUT
  /// prompting — so the overview/sport counts are live from app start for users
  /// who granted it during onboarding, without forcing a dialog on the rest (they
  /// are still prompted the first time they open the Sport tab via [ensureStarted]).
  Future<void> startIfPermitted() async {
    if (_subscription != null) {
      return;
    }
    if (await Permission.activityRecognition.isGranted) {
      await _startStream();
    }
  }

  Future<void> _startStream() async {
    _denied = false;
    final stored = await _store.loadStepsBaseline();
    _baseline = stored == null
        ? null
        : StepBaseline(date: stored.date, counter: stored.counter);
    _subscription = Pedometer.stepCountStream.listen(_onStep, onError: (_) {});
  }

  void _onStep(StepCount event) {
    final today = _dateKey(event.timeStamp);
    final current =
        _baseline ?? StepBaseline(date: today, counter: event.steps);
    final result = current.update(today, event.steps);
    if (result.baseline.counter != _baseline?.counter ||
        result.baseline.date != _baseline?.date) {
      _store.saveStepsBaseline(result.baseline.date, result.baseline.counter);
    }
    _baseline = result.baseline;
    _todaySteps = result.today;
    notifyListeners();
    _maybePersistToday();
  }

  /// How often the live step count is backed up while walking. The pedometer
  /// fires per step, so a throttle keeps this from writing secure storage (and
  /// hitting the backend) on every one.
  static const _persistEvery = Duration(minutes: 2);
  DateTime? _lastPersistAt;
  int _lastPersistedSteps = 0;

  /// Persist today's steps if enough time has passed since the last backup.
  void _maybePersistToday() {
    final last = _lastPersistAt;
    if (last != null && DateTime.now().difference(last) < _persistEvery) {
      return;
    }
    flushToday();
  }

  /// Back up today's live steps into the archive (and, via [mergeArchive], to the
  /// backend) so they survive a reinstall — the pedometer baseline lives in
  /// secure storage and is wiped with the app, so the account is the only durable
  /// copy. Steps are authoritative; distance/calories are left to whatever Health
  /// set (or 0 → the UI re-estimates them from steps + stride). Also called on app
  /// pause for a final flush. No-op when nothing new to store.
  Future<void> flushToday() async {
    final steps = todaySteps;
    if (steps <= 0 || steps == _lastPersistedSteps) {
      return;
    }
    _lastPersistAt = DateTime.now();
    _lastPersistedSteps = steps;
    final existing = _todayArchive;
    await mergeArchive([
      DailyActivity(
        dateKey: _paddedTodayKey(),
        steps: steps,
        distanceKm: existing?.distanceKm ?? 0,
        calories: existing?.calories ?? 0,
      ),
    ]);
  }

  String _dateKey(DateTime time) => '${time.year}-${time.month}-${time.day}';

  /// Today's date in the archive format `yyyy-mm-dd` (zero-padded, like in the
  /// [HealthImporter]) — the pedometer key above is intentionally unpadded.
  String _paddedTodayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
