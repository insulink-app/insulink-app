import 'dart:math';

import 'cardio_activity_classifier.dart';
import 'cardio_models.dart';

/// Segments a GPS log into endurance trainings. Pure and plugin-free (local
/// haversine) so it is unit-testable. Consecutive points moving faster than
/// [_walkMinKmh] with gaps up to [_maxGap] form a segment; brief stops (a
/// traffic light / crossing) up to [_maxPause] are tolerated inside a segment so
/// a short standstill does not split one ride into two. Segments below
/// [_minDuration] or [_minDistanceM] are dropped. Each surviving segment is typed
/// by [CardioActivityClassifier] — the recognised activity (from the optional
/// `activityLog`) when available, else average speed — which also discards
/// segments recognised as a vehicle (bus/train).
class CardioDetector {
  static const _walkMinKmh = 3.0;
  static const _maxGap = Duration(minutes: 5);

  /// How long a standstill inside an otherwise-moving segment is tolerated
  /// before the segment is closed — bridges red lights and short stops.
  static const _maxPause = Duration(minutes: 3);
  static const _minDuration = Duration(minutes: 8);
  static const _minDistanceM = 500.0;

  const CardioDetector();

  /// Detects trainings in [log]. The optional [activityLog] (empty by default,
  /// preserving the pure speed behaviour) lets the classifier reject vehicles and
  /// confirm a real ride via the OS activity recognition.
  List<CardioTraining> detect(
    List<TrackPoint> log, [
    List<ActivitySample> activityLog = const [],
  ]) {
    final trainings = <CardioTraining>[];
    for (final segment in _segment(log)) {
      if (!_qualifies(segment)) {
        continue;
      }
      final type = const CardioActivityClassifier().classify(
        startMs: segment.first.tMs,
        endMs: segment.last.tMs,
        avgKmh: _avgKmh(segment),
        activityLog: activityLog,
      );
      if (type == null) {
        continue;
      }
      trainings.add(_toTraining(segment, type));
    }
    return trainings;
  }

  /// Groups moving stretches into segments. A standstill (speed below
  /// [_walkMinKmh]) stays inside the current segment as long as it lasts at most
  /// [_maxPause]; a longer pause or a data gap over [_maxGap] closes the segment,
  /// trimming the trailing standstill down to the last moving point.
  List<List<TrackPoint>> _segment(List<TrackPoint> log) {
    final segments = <List<TrackPoint>>[];
    var current = <TrackPoint>[];
    var lastMovingTMs = 0;

    void close() {
      final trimmed = [
        for (final point in current)
          if (point.tMs <= lastMovingTMs) point,
      ];
      if (trimmed.length >= 2) {
        segments.add(trimmed);
      }
      current = <TrackPoint>[];
    }

    for (var index = 1; index < log.length; index++) {
      final previous = log[index - 1];
      final point = log[index];
      final gap = Duration(milliseconds: point.tMs - previous.tMs);
      if (gap <= Duration.zero || gap > _maxGap) {
        close();
        continue;
      }
      if (_speedKmh(previous, point, gap) >= _walkMinKmh) {
        if (current.isEmpty) {
          current.add(previous);
          lastMovingTMs = previous.tMs;
        }
        current.add(point);
        lastMovingTMs = point.tMs;
      } else if (current.isNotEmpty) {
        if (Duration(milliseconds: point.tMs - lastMovingTMs) <= _maxPause) {
          current.add(point);
        } else {
          close();
        }
      }
    }
    close();
    return segments;
  }

  bool _qualifies(List<TrackPoint> segment) {
    return _duration(segment) >= _minDuration &&
        _distanceM(segment) >= _minDistanceM;
  }

  CardioTraining _toTraining(List<TrackPoint> segment, CardioType type) {
    return CardioTraining(
      id: 'auto-${segment.first.tMs.toRadixString(36)}',
      type: type,
      startMs: segment.first.tMs,
      endMs: segment.last.tMs,
      track: List.unmodifiable(segment),
      distanceM: _distanceM(segment),
      detected: true,
    );
  }

  double _avgKmh(List<TrackPoint> segment) {
    final seconds = _duration(segment).inSeconds;
    if (seconds == 0) {
      return 0;
    }
    return _distanceM(segment) / seconds * 3.6;
  }

  Duration _duration(List<TrackPoint> segment) =>
      Duration(milliseconds: segment.last.tMs - segment.first.tMs);

  double _distanceM(List<TrackPoint> segment) {
    var total = 0.0;
    for (var index = 1; index < segment.length; index++) {
      total += _haversineM(segment[index - 1], segment[index]);
    }
    return total;
  }

  double _speedKmh(TrackPoint from, TrackPoint to, Duration gap) =>
      _haversineM(from, to) / gap.inSeconds * 3.6;

  double _haversineM(TrackPoint from, TrackPoint to) {
    const earthM = 6371000.0;
    final dLat = _radians(to.lat - from.lat);
    final dLng = _radians(to.lng - from.lng);
    final lat1 = _radians(from.lat);
    final lat2 = _radians(to.lat);
    final h =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    return earthM * 2 * atan2(sqrt(h), sqrt(1 - h));
  }

  double _radians(double degrees) => degrees * pi / 180;
}
