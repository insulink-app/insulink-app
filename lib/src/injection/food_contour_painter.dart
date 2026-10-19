import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:insulink/src/injection/food_contours.dart';

/// Lights the food's outlines ([FoodContours.toImage], white on transparent)
/// in [accent] where the scan line is. [lineCenter] is the line's middle as a
/// fraction of the picture's height and [intensity] how strongly it lights
/// (fading out where the line turns at the top and bottom). With [lineCenter]
/// null (reduced motion) every outline rests at a soft, even brightness.
///
/// The outline image is stretched with smooth filtering and drawn three times:
/// a wide blurred glow, then a slightly blurred copy that thickens the thin
/// edges and the sharp lines, both screened over it so the core of a line
/// brightens without burning out to white; a vertical gradient around the line then masks all
/// three, so only a band of the food around the line lights up.
class FoodContourPainter extends CustomPainter {
  const FoodContourPainter({
    required this.outlines,
    required this.accent,
    required this.lineCenter,
    required this.intensity,
  });

  final ui.Image outlines;
  final Color accent;
  final double? lineCenter;
  final double intensity;

  /// How far above and below the line the outlines still glow.
  static const double _reach = 0.09;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    final source = Rect.fromLTWH(
      0,
      0,
      outlines.width.toDouble(),
      outlines.height.toDouble(),
    );
    canvas.saveLayer(area, Paint());
    canvas.drawImageRect(outlines, source, area, _tinted(0.9, blur: 6));
    canvas.drawImageRect(
      outlines,
      source,
      area,
      _tinted(1, blur: 1.5)..blendMode = BlendMode.screen,
    );
    canvas.drawImageRect(
      outlines,
      source,
      area,
      _tinted(1)..blendMode = BlendMode.screen,
    );
    canvas.drawRect(area, _mask(area));
    canvas.restore();
  }

  Paint _tinted(double alpha, {double? blur}) => Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = ColorFilter.mode(
      accent.withValues(alpha: alpha),
      BlendMode.srcIn,
    )
    ..imageFilter = blur == null
        ? null
        : ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur);

  /// Keeps the outlines only in a soft band around the line.
  Paint _mask(Rect area) {
    final paint = Paint()..blendMode = BlendMode.dstIn;
    if (lineCenter == null) {
      return paint..color = Colors.white.withValues(alpha: 0.6);
    }
    final center = lineCenter!;
    final peak = Colors.white.withValues(alpha: intensity);
    final half = Colors.white.withValues(alpha: intensity * 0.7);
    return paint
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, half, peak, half, Colors.transparent],
        stops: [
          (center - _reach).clamp(0, 1),
          (center - _reach / 2).clamp(0, 1),
          center.clamp(0, 1),
          (center + _reach / 2).clamp(0, 1),
          (center + _reach).clamp(0, 1),
        ],
      ).createShader(area);
  }

  @override
  bool shouldRepaint(FoodContourPainter oldDelegate) =>
      oldDelegate.lineCenter != lineCenter ||
      oldDelegate.intensity != intensity ||
      oldDelegate.outlines != outlines ||
      oldDelegate.accent != accent;
}
