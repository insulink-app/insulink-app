import 'dart:math';

import 'cardio_models.dart';

/// Segments a GPS log into endurance trainings by speed. Pure and plugin-free
/// (local haversine) so it is unit-testable. Consecutive points moving faster
/// than [_walkMinKmh] with gaps up to [_maxGap] form a segment; segments below
/// [_minDuration] or [_minDistanceM] are dropped; the average speed maps to
/// walk/jog/bike. `ponytail:` threshold segmentation over the coarse ~60 s log
/// is enough to catch a real run/ride; a proper activity classifier is the
/// upgrade path if false positives appear.
class CardioDetector {
  static const _walkMinKmh = 3.0;
  static const _maxGap = Duration(minutes: 5);
  static const _minDuration = Duration(minutes: 8);
  static const _minDistanceM = 500.0;

  const CardioDetector();

  List<CardioTraining> detect(List<TrackPoint> log) {
    return [
      for (final segment in _segment(log))
        if (_qualifies(segment)) _toTraining(segment),
    ];
  }

  List<List<TrackPoint>> _segment(List<TrackPoint> log) {
    final segments = <List<TrackPoint>>[];
    var current = <TrackPoint>[];
    for (var index = 1; index < log.length; index++) {
      final previous = log[index - 1];
      final point = log[index];
      final gap = Duration(milliseconds: point.tMs - previous.tMs);
      if (_isMoving(previous, point, gap)) {
        if (current.isEmpty) {
          current.add(previous);
        }
        current.add(point);
      } else if (current.isNotEmpty) {
        segments.add(current);
        current = <TrackPoint>[];
      }
    }
    if (current.isNotEmpty) {
      segments.add(current);
    }
    return segments;
  }

  bool _isMoving(TrackPoint from, TrackPoint to, Duration gap) {
    if (gap <= Duration.zero || gap > _maxGap) {
      return false;
    }
    return _speedKmh(from, to, gap) >= _walkMinKmh;
  }

  bool _qualifies(List<TrackPoint> segment) {
    return _duration(segment) >= _minDuration &&
        _distanceM(segment) >= _minDistanceM;
  }

  CardioTraining _toTraining(List<TrackPoint> segment) {
    final distance = _distanceM(segment);
    final seconds = _duration(segment).inSeconds;
    final avgKmh = seconds == 0 ? 0.0 : distance / seconds * 3.6;
    return CardioTraining(
      id: 'auto-${segment.first.tMs.toRadixString(36)}',
      type: _classify(avgKmh),
      startMs: segment.first.tMs,
      endMs: segment.last.tMs,
      track: List.unmodifiable(segment),
      distanceM: distance,
      detected: true,
    );
  }

  CardioType _classify(double avgKmh) {
    if (avgKmh > 15) {
      return CardioType.bike;
    }
    if (avgKmh > 7) {
      return CardioType.jog;
    }
    return CardioType.walk;
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
