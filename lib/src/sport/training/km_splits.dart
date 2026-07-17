import 'package:geolocator/geolocator.dart';

import 'cardio_models.dart';

/// One kilometre of a training: its [km] length (1.0 except a trailing partial)
/// and the [time] spent covering it.
class KmSplit {
  final int index;
  final double km;
  final Duration time;

  const KmSplit({required this.index, required this.km, required this.time});

  /// Pace in seconds per kilometre (0 for a zero-length split).
  double get paceSecPerKm =>
      km == 0 ? 0 : time.inMilliseconds / Duration.millisecondsPerSecond / km;
}

/// One instantaneous speed reading: [kmh] over a track segment, timestamped at
/// the segment's midpoint [tMs] (epoch ms).
class SpeedSample {
  final int tMs;
  final double kmh;

  const SpeedSample({required this.tMs, required this.kmh});
}

/// Per-segment speed (km/h) along a [track], each timestamped at the segment
/// midpoint. Derived from the GPS fixes — the track carries no stored speed.
/// Segments with no elapsed time are skipped (a duplicate-timestamp fix).
List<SpeedSample> trackSpeeds(List<TrackPoint> track) {
  final samples = <SpeedSample>[];
  for (var index = 1; index < track.length; index++) {
    final prev = track[index - 1];
    final curr = track[index];
    final seconds =
        (curr.tMs - prev.tMs) / Duration.millisecondsPerSecond;
    if (seconds <= 0) {
      continue;
    }
    final meters = Geolocator.distanceBetween(
      prev.lat,
      prev.lng,
      curr.lat,
      curr.lng,
    );
    samples.add(
      SpeedSample(tMs: (prev.tMs + curr.tMs) ~/ 2, kmh: meters / seconds * 3.6),
    );
  }
  return samples;
}

/// Per-kilometre splits from a [track], interpolating the exact time each km
/// mark is crossed within the segment that crosses it (so a split isn't rounded
/// to a GPS-fix boundary). The final entry is the leftover distance (< 1 km).
List<KmSplit> kmSplits(List<TrackPoint> track) {
  if (track.length < 2) {
    return const [];
  }
  final splits = <KmSplit>[];
  var cumDist = 0.0;
  var boundaryDist = 0.0;
  var boundaryMs = track.first.tMs.toDouble();
  for (var index = 1; index < track.length; index++) {
    final prev = track[index - 1];
    final curr = track[index];
    final segStart = cumDist;
    final segDist = Geolocator.distanceBetween(
      prev.lat,
      prev.lng,
      curr.lat,
      curr.lng,
    );
    cumDist += segDist;
    while (cumDist >= boundaryDist + 1000) {
      final target = boundaryDist + 1000;
      final into = segDist == 0 ? 0.0 : (target - segStart) / segDist;
      final crossMs = prev.tMs + (curr.tMs - prev.tMs) * into;
      splits.add(
        KmSplit(
          index: splits.length + 1,
          km: 1.0,
          time: Duration(milliseconds: (crossMs - boundaryMs).round()),
        ),
      );
      boundaryDist = target;
      boundaryMs = crossMs;
    }
  }
  final leftover = cumDist - boundaryDist;
  if (leftover > 50) {
    splits.add(
      KmSplit(
        index: splits.length + 1,
        km: leftover / 1000,
        time: Duration(milliseconds: (track.last.tMs - boundaryMs).round()),
      ),
    );
  }
  return splits;
}
