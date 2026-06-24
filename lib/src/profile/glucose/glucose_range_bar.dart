import 'package:flutter/material.dart';
import 'package:insulink/src/base/track_bar.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';

/// A track (min..max mg/dL) with the selected [low]..[high] band filled in.
class GlucoseRangeBar extends StatelessWidget {
  const GlucoseRangeBar({
    super.key,
    required this.low,
    required this.high,
    required this.color,
    this.height = 8,
  });

  final int low, high;
  final Color color;
  final double height;

  static const _min = ProfileGlucoseState.minMgdl;
  static const _max = ProfileGlucoseState.maxMgdl;

  double _fraction(int value) => (value - _min) / (_max - _min);

  @override
  Widget build(BuildContext context) {
    return TrackBar(
      startFraction: _fraction(low),
      endFraction: _fraction(high),
      color: color,
      height: height,
    );
  }
}
