import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// The outlines on a meal photo, for the analysing animation to light up: the
/// crust of a slice, a plate's rim, the round of a macaroon. A Sobel filter on a
/// small greyscale copy finds where the brightness jumps, and every place gets
/// an [alphas] value from 0 (flat) to 1 (a sharp edge).
///
/// The values ramp softly instead of cutting at a threshold, and the result is
/// drawn as one image stretched with smooth filtering ([toImage]), so the
/// outlines read as continuous lines, not as a grid of dots. Strength is
/// measured against the sharpest three percent, not the single sharpest
/// place, and lifted by a power of 0.7 (gentler than a square root, which
/// lit a wooden table's grain): a white plate rim on a dark table would
/// otherwise leave the crust of the food itself pale.
class FoodContours {
  const FoodContours(this.width, this.height, this.alphas);

  /// Width of the copy the edges are found on: fine enough for a slice's
  /// crust, small enough to run in a few milliseconds on the UI isolate.
  static const int gridWidth = 240;

  /// The share of the sharpest places that reach full strength.
  static const double _keptShare = 0.08;

  /// Below this gradient a place is never an edge, however flat the photo.
  static const double _minimumGradient = 60;

  final int width;
  final int height;
  final Float32List alphas;

  /// Decodes [jpeg] straight to [gridWidth] wide and finds its outlines.
  static Future<FoodContours> fromJpeg(Uint8List jpeg) async {
    final codec = await ui.instantiateImageCodec(jpeg, targetWidth: gridWidth);
    final image = (await codec.getNextFrame()).image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final contours = FoodContours.fromRgba(
      image.width,
      image.height,
      pixels!.buffer.asUint8List(),
    );
    image.dispose();
    codec.dispose();
    return contours;
  }

  /// The outlines of a [width] × [height] picture given as RGBA bytes.
  factory FoodContours.fromRgba(int width, int height, Uint8List rgba) {
    final gradients = _SobelGrid(width, height, rgba).gradients();
    final sorted = Float64List.fromList(gradients)..sort();
    final edge = math.max(
      _percentile(sorted, 1 - _keptShare),
      _minimumGradient,
    );
    final sharp = math.max(_percentile(sorted, 0.97), edge + 1);
    final floor = edge * 0.6;
    return FoodContours(
      width,
      height,
      Float32List.fromList([
        for (final gradient in gradients)
          math
              .pow(((gradient - floor) / (sharp - floor)).clamp(0, 1), 0.7)
              .toDouble(),
      ]),
    );
  }

  static double _percentile(Float64List sorted, double share) =>
      sorted[(share * (sorted.length - 1)).round()];

  /// The outlines as a white image whose alpha is the edge strength, to be
  /// tinted when drawn.
  Future<ui.Image> toImage() {
    final pixels = Uint8List(width * height * 4);
    for (var index = 0; index < alphas.length; index++) {
      pixels.setAll(index * 4, [255, 255, 255, (alphas[index] * 255).round()]);
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}

/// The Sobel gradient of every pixel of a greyscale copy; the border stays 0.
class _SobelGrid {
  _SobelGrid(this.width, this.height, Uint8List rgba)
    : _grey = Float64List.fromList([
        for (var pixel = 0; pixel < width * height; pixel++)
          0.299 * rgba[pixel * 4] +
              0.587 * rgba[pixel * 4 + 1] +
              0.114 * rgba[pixel * 4 + 2],
      ]);

  final int width;
  final int height;
  final Float64List _grey;

  Float64List gradients() {
    final result = Float64List(width * height);
    for (var row = 1; row < height - 1; row++) {
      for (var column = 1; column < width - 1; column++) {
        result[row * width + column] = _gradientAt(column, row);
      }
    }
    return result;
  }

  double _gradientAt(int column, int row) {
    final horizontal =
        _at(column + 1, row - 1) +
        2 * _at(column + 1, row) +
        _at(column + 1, row + 1) -
        _at(column - 1, row - 1) -
        2 * _at(column - 1, row) -
        _at(column - 1, row + 1);
    final vertical =
        _at(column - 1, row + 1) +
        2 * _at(column, row + 1) +
        _at(column + 1, row + 1) -
        _at(column - 1, row - 1) -
        2 * _at(column, row - 1) -
        _at(column + 1, row - 1);
    return ui.Offset(horizontal, vertical).distance;
  }

  double _at(int column, int row) => _grey[row * width + column];
}
