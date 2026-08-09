import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/overview/chart/chart_window.dart';

/// The window's right edge decides which stretch of time the chart is looking at.
/// Pinning it to the newest reading made a long outage slide the whole window
/// backwards, so the oldest hours fell off the left and the gap never appeared on
/// the right — the "data disappears from the front" report.
void main() {
  final sensorStart = DateTime(2026, 8, 1, 6);
  final now = sensorStart.add(const Duration(hours: 30));

  int secsSinceStart(Duration sinceStart) => sinceStart.inSeconds;

  test('a live sensor puts the edge at the newest reading, as before', () {
    final edge = liveWindowEdgeSecs(
      latestSecs: secsSinceStart(const Duration(hours: 30)),
      sensorStart: sensorStart,
      now: now,
    );
    expect(edge, secsSinceStart(const Duration(hours: 30)));
  });

  test('during an outage the edge stays at now, not at the last reading', () {
    final edge = liveWindowEdgeSecs(
      latestSecs: secsSinceStart(const Duration(hours: 24)),
      sensorStart: sensorStart,
      now: now,
    );
    expect(edge, secsSinceStart(const Duration(hours: 30)));
  });

  /// The whole point: the 24 h window must still start at now-24h, so it covers
  /// the archive slice the chart is handed instead of reaching past its start.
  test('the outage does not drag the window start back past the data', () {
    const range = Duration(hours: 24);
    final edge = liveWindowEdgeSecs(
      latestSecs: secsSinceStart(const Duration(hours: 24)),
      sensorStart: sensorStart,
      now: now,
    );
    final windowStart = edge - range.inSeconds;
    expect(windowStart, secsSinceStart(const Duration(hours: 6)));
  });

  test('a reading ahead of now is not clipped off the edge', () {
    final edge = liveWindowEdgeSecs(
      latestSecs: secsSinceStart(const Duration(hours: 31)),
      sensorStart: sensorStart,
      now: now,
    );
    expect(edge, secsSinceStart(const Duration(hours: 31)));
  });

  test('without a session clock the newest reading still anchors it', () {
    final edge = liveWindowEdgeSecs(
      latestSecs: 4200,
      sensorStart: null,
      now: now,
    );
    expect(edge, 4200);
  });
}
