import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'cardio_models.dart';

/// Zeichnet ein laufendes Ausdauer-Training per GPS auf: abonniert den
/// [Geolocator]-Positionsstream, sammelt [TrackPoint]s, summiert die Strecke
/// inkrementell (Haversine via [Geolocator.distanceBetween]) und liefert Dauer +
/// aktuelle Geschwindigkeit. UI-frei; die Recording-Page hört als [ChangeNotifier]
/// zu. `ponytail:` — läuft nur im App-Vordergrund; ein Foreground-Service für
/// Bildschirm-aus-Tracking wäre der nächste Ausbau, falls gewünscht.
class CardioTracker extends ChangeNotifier {
  final CardioType type;
  final List<TrackPoint> _points = [];
  final DateTime _startedAt = DateTime.now();

  StreamSubscription<Position>? _subscription;
  Position? _lastFix;
  double _distanceM = 0;
  double _currentSpeedKmh = 0;

  CardioTracker(this.type);

  List<TrackPoint> get points => List.unmodifiable(_points);
  double get distanceM => _distanceM;
  double get currentSpeedKmh => _currentSpeedKmh;
  Duration get elapsed => DateTime.now().difference(_startedAt);
  TrackPoint? get latest => _points.isEmpty ? null : _points.last;

  /// Fragt die Standort-Berechtigung an und startet den Positionsstream.
  /// Gibt false zurück, wenn Dienst aus oder Berechtigung verweigert ist.
  Future<bool> start() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }
    _subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onPosition);
    return true;
  }

  void _onPosition(Position fix) {
    if (_lastFix != null) {
      _distanceM += Geolocator.distanceBetween(
        _lastFix!.latitude,
        _lastFix!.longitude,
        fix.latitude,
        fix.longitude,
      );
    }
    _lastFix = fix;
    _currentSpeedKmh = fix.speed < 0 ? 0 : fix.speed * 3.6;
    _points.add(TrackPoint(
      lat: fix.latitude,
      lng: fix.longitude,
      tMs: DateTime.now().millisecondsSinceEpoch,
    ));
    notifyListeners();
  }

  /// Aufzeichnung beenden und das fertige Training bauen.
  CardioTraining finish() {
    _subscription?.cancel();
    _subscription = null;
    return CardioTraining(
      id: _startedAt.microsecondsSinceEpoch.toRadixString(36),
      type: type,
      startMs: _startedAt.millisecondsSinceEpoch,
      endMs: DateTime.now().millisecondsSinceEpoch,
      track: List.unmodifiable(_points),
      distanceM: _distanceM,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
