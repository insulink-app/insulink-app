import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/sleep_hypnogram.dart';

SleepSegment seg(SleepStage stage, int startMin, int endMin) => SleepSegment(
  stage: stage,
  startMs: startMin * 60 * 1000,
  endMs: endMin * 60 * 1000,
);

void main() {
  const minMs = 5 * 60 * 1000;

  test('a short blip is absorbed and the surrounding stage coalesces', () {
    final smoothed = mergeShortSleepSegments([
      seg(SleepStage.light, 0, 30),
      seg(SleepStage.awake, 30, 32), // 2 min blip < 5 min
      seg(SleepStage.light, 32, 60),
    ], minMs: minMs);
    expect(smoothed.length, 1);
    expect(smoothed.first.stage, SleepStage.light);
    expect(smoothed.first.startMs, 0);
    expect(smoothed.first.endMs, 60 * 60 * 1000);
  });

  test('long stretches are kept as distinct phases', () {
    final smoothed = mergeShortSleepSegments([
      seg(SleepStage.light, 0, 30),
      seg(SleepStage.deep, 30, 60),
      seg(SleepStage.rem, 60, 90),
    ], minMs: minMs);
    expect(smoothed.map((s) => s.stage).toList(), [
      SleepStage.light,
      SleepStage.deep,
      SleepStage.rem,
    ]);
  });
}
