import 'package:latlong2/latlong.dart';

import 'cardio_models.dart';

/// Position on [track] at epoch-[ms], linearly interpolated between the two
/// surrounding fixes so a chart hover lands on the map even between recorded
/// points. Returns null for an empty track; clamps to the first/last fix when
/// [ms] is outside the recorded span. [track] must be ascending in time.
LatLng? trackPositionAt(List<TrackPoint> track, int ms) {
  if (track.isEmpty) {
    return null;
  }
  if (ms <= track.first.tMs) {
    return LatLng(track.first.lat, track.first.lng);
  }
  if (ms >= track.last.tMs) {
    return LatLng(track.last.lat, track.last.lng);
  }
  for (var index = 1; index < track.length; index++) {
    final next = track[index];
    if (next.tMs >= ms) {
      return _lerp(track[index - 1], next, ms);
    }
  }
  return LatLng(track.last.lat, track.last.lng);
}

/// Linearly interpolates between two fixes at the fraction [ms] sits from
/// [prev] to [next] (guards a zero-width interval).
LatLng _lerp(TrackPoint prev, TrackPoint next, int ms) {
  final span = next.tMs - prev.tMs;
  final fraction = span == 0 ? 0.0 : (ms - prev.tMs) / span;
  return LatLng(
    prev.lat + (next.lat - prev.lat) * fraction,
    prev.lng + (next.lng - prev.lng) * fraction,
  );
}
