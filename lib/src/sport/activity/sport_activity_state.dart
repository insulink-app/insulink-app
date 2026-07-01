import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../sport_models.dart';
import '../sport_store.dart';
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

  /// Upsert imported days (by [DailyActivity.dateKey]) and persist.
  Future<void> mergeArchive(List<DailyActivity> days) async {
    final byDate = {for (final day in _archive) day.dateKey: day};
    for (final day in days) {
      byDate[day.dateKey] = day;
    }
    _archive = byDate.values.toList()
      ..sort((first, second) => first.dateKey.compareTo(second.dateKey));
    notifyListeners();
    await _store.saveActivityArchive(_archive);
  }

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
  /// or weight).
  double? get importedDistanceKm =>
      _importedDistanceKm ?? _todayArchive?.distanceKm;
  double? get importedCalories => _importedCalories ?? _todayArchive?.calories;

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
