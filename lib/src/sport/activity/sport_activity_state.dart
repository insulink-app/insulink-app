import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

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

  SportActivityState([this._store = const SportStore()]);

  /// Importierte Schritte (Google Health) haben Vorrang vor dem Schrittzähler.
  int get todaySteps => _importedSteps ?? _todaySteps ?? 0;

  /// Echte Werte aus Google Health, falls importiert — sonst null (dann
  /// schätzt die Kachel aus Schritten + Schrittlänge bzw. Gewicht).
  double? get importedDistanceKm => _importedDistanceKm;
  double? get importedCalories => _importedCalories;

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

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
