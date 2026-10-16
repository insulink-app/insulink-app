import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The meal camera's zoom: where it is between the lens's [min] and [max]. A
/// swipe up zooms in, a swipe down zooms out, by a factor rather than a step, so
/// the same swipe feels the same at 0.5x and at 4x.
class CameraZoom {
  const CameraZoom({required this.min, required this.max, required this.level});

  /// A digital zoom past this only blurs the plate.
  static const _ceiling = 8.0;

  /// Swipe distance in logical pixels that doubles (or halves) the zoom.
  static const _doublingDistance = 200.0;

  final double min;
  final double max;
  final double level;

  /// The zoom after a vertical drag of [deltaY] (negative is upwards).
  CameraZoom swiped(double deltaY) {
    final scaled = level * math.pow(2, -deltaY / _doublingDistance);
    return CameraZoom(
      min: min,
      max: max,
      level: scaled.clamp(min, math.min(max, _ceiling)).toDouble(),
    );
  }

  /// "0,5×", "2×": one decimal, none when it is whole.
  String get label {
    final rounded = (level * 10).round() / 10;
    return '${sportDecimal(rounded, rounded % 1 == 0 ? 0 : 1)}×';
  }
}

/// The current zoom as a small dark pill above the hint, so a swipe shows what
/// it did.
class CameraZoomPill extends StatelessWidget {
  const CameraZoomPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(InkRadius.field),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(label, style: InkText.label.copyWith(color: Colors.white)),
      ),
    );
  }
}
