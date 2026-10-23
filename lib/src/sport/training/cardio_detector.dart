import 'dart:math';

import 'cardio_activity_classifier.dart';
import 'cardio_models.dart';
import 'heart_effort.dart';

/// Segments a GPS log into endurance trainings. Pure and plugin-free (local
/// haversine) so it is unit-testable. Consecutive points moving faster than
/// [_walkMinKmh] with gaps up to [_maxGap] form a segment; brief stops (a
/// traffic light / crossing) up to [_maxPause] are tolerated inside a segment so
/// a short standstill does not split one ride into two. A segment that changes
/// between riding and going on foot is cut there ([_splitAtRides]), so stepping
/// off a bus and walking on yields a walk without the bus. Segments below
/// [_minDuration] or [_minDistanceM] are dropped. Each surviving segment is typed
/// by [CardioActivityClassifier] — the recognised activity (from the optional
/// `activityLog`) when available, else average speed — which also discards
/// vehicle rides (bus/train/car: recognised as a vehicle AND reaching vehicle
/// speed, see [_topKmh]). The optional [HeartRateEvidence] adds the effort the
/// band measured over each segment.
class CardioDetector {
  static const _walkMinKmh = 3.0;
  static const _maxGap = Duration(minutes: 5);

  /// How long a standstill inside an otherwise-moving segment is tolerated
  /// before the segment is closed — bridges red lights and short stops.
  static const _maxPause = Duration(minutes: 3);
  static const _minDuration = Duration(minutes: 8);
  static const _minDistanceM = 500.0;

  /// Speed between two fixes (km/h) nobody reaches on foot: a stretch with it
  /// is a ride, on a bike or in a vehicle.
  static const _ridingKmh = 20.0;

  /// The fastest average (km/h) a calm stretch is cut off at: walking or an
  /// easy jog. A slower stretch of a bike ride (12 km/h uphill) stays put.
  static const _onFootMaxKmh = 10.0;

  /// Riding fixes a segment needs before it is cut at all. A GPS jump inside a
  /// walk makes two (out and back), so two jumps never split it; a real ride
  /// makes dozens at the 5 to 10 s detect cadence.
  static const _minRidingFixes = 6;

  const CardioDetector();

  /// Detects trainings in [log]. The optional [activityLog] (empty by default,
  /// preserving the pure speed behaviour) lets the classifier reject vehicles and
  /// confirm a real ride via the OS activity recognition; the optional [heart]
  /// lets the pulse reject a passive ride and recognise a jog.
  List<CardioTraining> detect(
    List<TrackPoint> log, [
    List<ActivitySample> activityLog = const [],
    HeartRateEvidence heart = HeartRateEvidence.none,
  ]) {
    final trainings = <CardioTraining>[];
    for (final segment in _segment(log).expand(_splitAtRides)) {
      if (!_qualifies(segment)) {
        continue;
      }
      final type = const CardioActivityClassifier().classify(
        startMs: segment.first.tMs,
        endMs: segment.last.tMs,
        avgKmh: _avgKmh(segment),
        topKmh: _topKmh(segment),
        activityLog: activityLog,
        effort: heart.effort(segment.first.tMs, segment.last.tMs),
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

  /// Cuts [segment] around every stretch at walking pace, without a riding fix,
  /// that qualifies as a training by itself. Shorter calm stretches (the walk to the stop, a
  /// slow climb on a bike) stay with the ride. The pair across each cut is
  /// dropped, so no two pieces share a point and both survive the runner's
  /// overlap check.
  List<List<TrackPoint>> _splitAtRides(List<TrackPoint> segment) {
    final riding = [
      for (var index = 1; index < segment.length; index++)
        _pairKmh(segment, index) > _ridingKmh,
    ];
    if (riding.where((fast) => fast).length < _minRidingFixes) {
      return [segment];
    }
    final starts = <int>{0};
    var calmFrom = 0;
    for (var pair = 0; pair <= riding.length; pair++) {
      if (pair < riding.length && !riding[pair]) {
        continue;
      }
      if (_isOnFoot(segment.sublist(calmFrom, pair + 1))) {
        starts
          ..add(calmFrom)
          ..add(pair + 1);
      }
      calmFrom = pair + 1;
    }
    final cuts = starts.where((start) => start < segment.length).toList()
      ..sort();
    return [
      for (var index = 0; index < cuts.length; index++)
        segment.sublist(
          cuts[index],
          index + 1 < cuts.length ? cuts[index + 1] : segment.length,
        ),
    ];
  }

  bool _isOnFoot(List<TrackPoint> stretch) =>
      _qualifies(stretch) && _avgKmh(stretch) <= _onFootMaxKmh;

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

  /// The 90th-percentile speed between consecutive points: the pace the segment
  /// actually reaches, robust to a single GPS jump. Tells a bike from a bus that
  /// averages the same but speeds up between stops.
  double _topKmh(List<TrackPoint> segment) {
    final speeds = [
      for (var index = 1; index < segment.length; index++)
        _pairKmh(segment, index),
    ]..sort();
    return speeds[((speeds.length - 1) * 0.9).round()];
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

  /// The speed from the point before [index] to the one at it.
  double _pairKmh(List<TrackPoint> segment, int index) => _speedKmh(
    segment[index - 1],
    segment[index],
    Duration(milliseconds: segment[index].tMs - segment[index - 1].tMs),
  );

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
