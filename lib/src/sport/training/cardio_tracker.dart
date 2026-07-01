import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'cardio_models.dart';

/// Records a running endurance workout via GPS: subscribes to the [Geolocator]
/// position stream, collects [TrackPoint]s, sums the distance incrementally
/// (Haversine via [Geolocator.distanceBetween]) and provides duration + current
/// speed. UI-free; the recording page listens as a [ChangeNotifier]. `ponytail:`
/// — runs only while the app is in the foreground; a foreground service for
/// screen-off tracking would be the next step, if wanted.
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

  /// Heading in degrees (0 = north, clockwise), or null when the GPS reports no
  /// reliable direction (standstill often returns -1).
  double? get currentHeadingDeg {
    final heading = _lastFix?.heading ?? -1;
    return heading < 0 ? null : heading;
  }

  Duration get elapsed => DateTime.now().difference(_startedAt);
  TrackPoint? get latest => _points.isEmpty ? null : _points.last;

  /// Requests location permission and starts the position stream. Returns false
  /// when the service is off or permission is denied.
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
    _points.add(
      TrackPoint(
        lat: fix.latitude,
        lng: fix.longitude,
        tMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    notifyListeners();
  }

  /// Stop recording and build the finished training.
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
