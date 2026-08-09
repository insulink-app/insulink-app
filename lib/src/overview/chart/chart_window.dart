import 'dart:math' as math;

/// Session-seconds of the live window's RIGHT EDGE — wall-clock now, not the
/// newest reading.
///
/// The chart used to pin the newest reading to the right edge. While a sensor is
/// delivering those are the same instant, but during an outage the whole window
/// slides back with the last reading: after six silent hours the 24 h window
/// covered `now-30h … now-6h`. Two things went wrong at once — the outage itself
/// was invisible (the stale reading sat at the edge as if it were current), and
/// the window reached six hours further back than the archive slice the chart is
/// handed (`now-24h … now`), so its left end had no data to draw. That empty left
/// end is the reported "data disappears from the front": nothing was lost, the
/// window had simply walked off the end of it.
///
/// Anchoring the edge to now keeps the window over the data that exists and lets
/// the gap open where it actually is — on the right. Readings keep their x origin
/// at [latestSecs] (the axis labels and the forecast hang off it); only the
/// window moves.
///
/// [latestSecs] still wins when it is ahead of now — a sensor whose session clock
/// runs slightly fast must not have its freshest reading clipped off the edge.
/// With no [sensorStart] there is no session clock to place now on, so the old
/// behaviour stands.
int liveWindowEdgeSecs({
  required int latestSecs,
  required DateTime? sensorStart,
  required DateTime now,
}) {
  if (sensorStart == null) {
    return latestSecs;
  }
  return math.max(latestSecs, now.difference(sensorStart).inSeconds);
}
