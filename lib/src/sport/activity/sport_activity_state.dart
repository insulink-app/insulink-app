import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../sport_models.dart';
import '../sport_store.dart';
import 'step_baseline.dart';

/// Liest die heutigen Schritte aus dem Hardware-Schrittzähler (`pedometer`).
/// Eigener [ChangeNotifier], weil der Stream-Lebenszyklus sich vom CRUD-Zustand
/// unterscheidet. Distanz/Kalorien werden NICHT hier berechnet (das sind
/// Schätzungen aus Schritten + Schrittlänge + Gewicht) — siehe
/// `activity_summary_card.dart`.
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

  /// Tages-Aktivitätsarchiv (aufsteigend nach Datum) für die Detail-Seiten.
  List<DailyActivity> get activityArchive => List.unmodifiable(_archive);

  /// Importierte Tage upserten (per [DailyActivity.dateKey]) und persistieren.
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

  /// Heutiger Archiv-Eintrag (aus dem letzten Health-Sync), falls vorhanden.
  /// Dient als **persistenter** Fallback, damit gesyncte Werte nach einem
  /// Neustart/Provider-Rebuild NICHT verschwinden (die `_imported*`-Felder sind
  /// nur sitzungsweit).
  DailyActivity? get _todayArchive {
    final key = _paddedTodayKey();
    for (final day in _archive) {
      if (day.dateKey == key) {
        return day;
      }
    }
    return null;
  }

  /// Heutige Schritte: frisch importiert > größerer Wert aus Pedometer bzw.
  /// gesynctem Archiv (so zählt der Schrittzähler live weiter, ohne dass der
  /// zuletzt gesyncte Stand verloren geht).
  int get todaySteps {
    if (_importedSteps != null) {
      return _importedSteps!;
    }
    final pedometer = _todaySteps ?? 0;
    final archived = _todayArchive?.steps ?? 0;
    return pedometer > archived ? pedometer : archived;
  }

  /// Echte Werte aus Google Health: frisch importiert bzw. der persistente
  /// heutige Archiv-Wert — sonst null (dann schätzt die Kachel aus Schritten +
  /// Schrittlänge bzw. Gewicht).
  double? get importedDistanceKm => _importedDistanceKm ?? _todayArchive?.distanceKm;
  double? get importedCalories => _importedCalories ?? _todayArchive?.calories;

  bool get permissionDenied => _denied;

  /// Heutige Werte aus Google Health übernehmen (Sitzung, nicht persistiert).
  void setImported({int? steps, double? distanceKm, double? calories}) {
    _importedSteps = steps;
    _importedDistanceKm = distanceKm;
    _importedCalories = calories;
    notifyListeners();
  }

  /// Fordert ACTIVITY_RECOGNITION an (falls nötig) und abonniert den
  /// Schrittzähler. Idempotent — beim ersten Öffnen des Sport-Tabs aufgerufen,
  /// nicht beim App-Start (der Onboarding-Schritt fragt die Berechtigung ab).
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

  /// Heutiges Datum im Archiv-Format `yyyy-mm-dd` (null-gepaddet, wie im
  /// [HealthImporter]) — der Pedometer-Schlüssel oben ist bewusst ungepaddet.
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
