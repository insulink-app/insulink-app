import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/meal_camera_zoom.dart';

/// A swipe zooms by a factor and never leaves what the lens can do, nor goes
/// past the digital ceiling where the plate only gets blurrier.
void main() {
  const widest = CameraZoom(min: 0.5, max: 20, level: 0.5);

  test('a swipe up zooms in, the same swipe down zooms back out', () {
    final zoomedIn = widest.swiped(-200);
    expect(zoomedIn.level, closeTo(1, 0.001));
    expect(zoomedIn.swiped(200).level, closeTo(0.5, 0.001));
  });

  test('the zoom stays between the lens minimum and the ceiling', () {
    expect(widest.swiped(500).level, 0.5);
    expect(widest.swiped(-5000).level, 8);
  });

  test('the label drops a whole number decimal', () {
    expect(widest.label, '0,5×');
    expect(widest.swiped(-400).label, '2×');
  });
}
