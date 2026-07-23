import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/sleep_metrics.dart';

void main() {
  int minutes(int m) => m * 60000;
  SleepSegment seg(SleepStage stage, int startMin, int endMin) =>
      SleepSegment(stage: stage, startMs: minutes(startMin), endMs: minutes(endMin));

  test('time to solid = onset of sleep to first deep stretch', () {
    final timeline = [
      seg(SleepStage.light, 0, 20),
      seg(SleepStage.deep, 20, 60),
    ];
    final metrics = SleepMetrics.of(const SleepStages(deep: 40, light: 20), timeline);
    expect(metrics.timeToSolidMinutes, 20);
  });

  test('no deep stretch => time to solid is null', () {
    final timeline = [seg(SleepStage.light, 0, 60)];
    final metrics = SleepMetrics.of(const SleepStages(light: 60), timeline);
    expect(metrics.timeToSolidMinutes, isNull);
  });

  test('index is 0 with no sleep and clamps to 0..100', () {
    final none = SleepMetrics.of(const SleepStages(awake: 60), null);
    expect(none.sleepIndex, 0);

    final good = SleepMetrics.of(
      const SleepStages(deep: 100, rem: 110, light: 260, awake: 10),
      null,
    );
    expect(good.sleepIndex, inInclusiveRange(0, 100));
    expect(good.sleepIndex, greaterThan(none.sleepIndex));
  });

  test('bar metrics pass the stage totals straight through', () {
    final metrics = SleepMetrics.of(
      const SleepStages(deep: 90, awake: 25, light: 200),
      null,
    );
    expect(metrics.deepMinutes, 90);
    expect(metrics.interruptionMinutes, 25);
  });
}
