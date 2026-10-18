import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/food_contours.dart';

/// The analysing animation lights the photo's outlines, so they must sit on
/// the edges of the food and nowhere on a flat surface.
void main() {
  Uint8List picture(int width, int height, int Function(int column) shade) {
    final rgba = Uint8List(width * height * 4);
    for (var pixel = 0; pixel < width * height; pixel++) {
      final grey = shade(pixel % width);
      rgba.setAll(pixel * 4, [grey, grey, grey, 255]);
    }
    return rgba;
  }

  test('outlines lie only on the border between dark and light', () {
    final contours = FoodContours.fromRgba(
      20,
      20,
      picture(20, 20, (column) => column < 10 ? 0 : 255),
    );
    for (var index = 0; index < contours.alphas.length; index++) {
      final column = index % 20;
      final onBorder = column >= 9 && column <= 10;
      if (!onBorder) {
        expect(contours.alphas[index], 0);
      }
      expect(contours.alphas[index], inInclusiveRange(0, 1));
    }
    expect(contours.alphas.any((alpha) => alpha > 0.9), isTrue);
  });

  test('a flat photo has no outlines', () {
    final contours = FoodContours.fromRgba(20, 20, picture(20, 20, (_) => 128));
    expect(contours.alphas.every((alpha) => alpha == 0), isTrue);
  });
}
