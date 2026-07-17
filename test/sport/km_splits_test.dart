import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/km_splits.dart';

void main() {
  test('no splits for a track under one point', () {
    expect(kmSplits(const []), isEmpty);
  });

  test('two ~1 km splits at a steady 5:00/km pace', () {
    // ~1 km per 0.009° latitude; 300 s each → 5:00/km.
    const track = [
      TrackPoint(lat: 0.000, lng: 0, tMs: 0),
      TrackPoint(lat: 0.009, lng: 0, tMs: 300000),
      TrackPoint(lat: 0.018, lng: 0, tMs: 600000),
    ];
    final splits = kmSplits(track);
    expect(splits.length, 2);
    for (final split in splits) {
      expect(split.km, 1.0);
      expect(split.paceSecPerKm, closeTo(300, 5));
    }
    expect(splits.first.index, 1);
    expect(splits.last.index, 2);
  });

  test('a partial trailing kilometre over 50 m is kept', () {
    const track = [
      TrackPoint(lat: 0.000, lng: 0, tMs: 0),
      TrackPoint(lat: 0.0135, lng: 0, tMs: 450000), // ~1.5 km
    ];
    final splits = kmSplits(track);
    expect(splits.length, 2);
    expect(splits.last.km, closeTo(0.5, 0.02));
  });

  test('trackSpeeds gives ~12 km/h at the segment midpoints', () {
    // ~1 km per 0.009° latitude covered in 300 s → 12 km/h.
    const track = [
      TrackPoint(lat: 0.000, lng: 0, tMs: 0),
      TrackPoint(lat: 0.009, lng: 0, tMs: 300000),
      TrackPoint(lat: 0.018, lng: 0, tMs: 600000),
    ];
    final speeds = trackSpeeds(track);
    expect(speeds.length, 2);
    expect(speeds.first.tMs, 150000);
    expect(speeds.last.tMs, 450000);
    for (final sample in speeds) {
      expect(sample.kmh, closeTo(12, 0.5));
    }
  });

  test('trackSpeeds skips a duplicate-timestamp segment', () {
    const track = [
      TrackPoint(lat: 0.000, lng: 0, tMs: 0),
      TrackPoint(lat: 0.009, lng: 0, tMs: 0),
    ];
    expect(trackSpeeds(track), isEmpty);
  });
}
