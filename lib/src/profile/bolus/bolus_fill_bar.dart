import 'package:flutter/material.dart';
import 'package:insulink/src/base/track_bar.dart';

/// A track (min..max) filled from the start up to [value].
class BolusFillBar extends StatelessWidget {
  const BolusFillBar({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    this.height = 8,
  });

  final int value, min, max;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return TrackBar(
      startFraction: 0,
      endFraction: (value - min) / (max - min),
      color: color,
      height: height,
    );
  }
}
