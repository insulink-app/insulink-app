import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/track_interpolation.dart';

void main() {
  const track = [
    TrackPoint(lat: 0, lng: 0, tMs: 1000),
    TrackPoint(lat: 2, lng: 4, tMs: 3000),
  ];

  test('null on empty track', () {
    expect(trackPositionAt(const [], 2000), isNull);
  });

  test('clamps to the first fix before the span', () {
    final at = trackPositionAt(track, 0)!;
    expect(at.latitude, 0);
    expect(at.longitude, 0);
  });

  test('clamps to the last fix after the span', () {
    final at = trackPositionAt(track, 9000)!;
    expect(at.latitude, 2);
    expect(at.longitude, 4);
  });

  test('interpolates halfway between two fixes', () {
    final at = trackPositionAt(track, 2000)!;
    expect(at.latitude, 1.0);
    expect(at.longitude, 2.0);
  });
}
