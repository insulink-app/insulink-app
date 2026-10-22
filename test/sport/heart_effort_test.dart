import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/google_health/intraday_pulse_store.dart';
import 'package:insulink/src/sport/training/cardio_activity_classifier.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/heart_effort.dart';

void main() {
  const minute = 60000;
  const startMs = 1000000000000;
  const endMs = startMs + 20 * minute;

  /// A day of [restBpm] before the segment, then [segmentBpm] during it.
  HeartRateEvidence pulse(int restBpm, int segmentBpm) => HeartRateEvidence([
    for (var offset = -24 * 60; offset <= 20; offset++)
      (
        at: DateTime.fromMillisecondsSinceEpoch(startMs + offset * minute),
        bpm: offset < 0 ? restBpm : segmentBpm,
      ),
  ]);

  CardioType? classify(
    double avgKmh,
    HeartRateEvidence heart, [
    ActivityKind? kind,
  ]) => const CardioActivityClassifier().classify(
    startMs: startMs,
    endMs: endMs,
    avgKmh: avgKmh,
    topKmh: avgKmh + 5,
    activityLog: [if (kind != null) ActivitySample(tMs: startMs, kind: kind)],
    effort: heart.effort(startMs, endMs),
  );

  test('effort grades the lift over the baseline', () {
    expect(pulse(55, 65).effort(startMs, endMs), HeartEffort.resting);
    expect(pulse(55, 95).effort(startMs, endMs), HeartEffort.light);
    expect(pulse(55, 140).effort(startMs, endMs), HeartEffort.hard);
  });

  test('too few samples read unknown', () {
    final sparse = HeartRateEvidence(<PulseSample>[
      (at: DateTime.fromMillisecondsSinceEpoch(startMs), bpm: 150),
    ]);
    expect(sparse.effort(startMs, endMs), HeartEffort.unknown);
    expect(HeartRateEvidence.none.effort(startMs, endMs), HeartEffort.unknown);
  });

  test('a bike-speed ride with the pulse at rest is discarded', () {
    expect(classify(20, pulse(55, 65)), isNull);
    expect(classify(20, pulse(55, 65), ActivityKind.vehicle), isNull);
  });

  test('a resting pulse does not discard a ride recognised as cycling', () {
    expect(classify(20, pulse(55, 65), ActivityKind.bike), CardioType.bike);
  });

  test('a working pulse keeps the bike ride', () {
    expect(classify(20, pulse(55, 120)), CardioType.bike);
  });

  test('jogging pace with a hard-working heart is a jog', () {
    expect(classify(9, pulse(55, 145)), CardioType.jog);
    expect(classify(9, pulse(55, 145), ActivityKind.run), CardioType.jog);
  });

  test('a slow hard walk stays a walk, as does a light jog pace', () {
    expect(classify(5, pulse(55, 145)), CardioType.walk);
    expect(classify(9, pulse(55, 95)), CardioType.walk);
  });

  test('without pulse data nothing changes', () {
    expect(classify(20, HeartRateEvidence.none), CardioType.bike);
    expect(classify(9, HeartRateEvidence.none), CardioType.walk);
  });
}
