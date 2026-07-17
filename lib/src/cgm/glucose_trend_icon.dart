import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Phosphor arrow for a per-minute glucose trend, in 5 directional buckets.
/// Shared so the overview headline and the workout vitals bar can never drift
/// apart on what "rising" looks like.
class GlucoseTrendIcon extends StatelessWidget {
  const GlucoseTrendIcon({
    super.key,
    required this.perMin,
    required this.color,
    required this.size,
  });

  final double perMin;
  final Color color;
  final double size;

  IconData get _arrow {
    if (perMin >= 2) {
      return PhosphorIconsBold.arrowUp;
    }
    if (perMin >= 1) {
      return PhosphorIconsBold.arrowUpRight;
    }
    if (perMin > -1) {
      return PhosphorIconsBold.arrowRight;
    }
    if (perMin > -2) {
      return PhosphorIconsBold.arrowDownRight;
    }
    return PhosphorIconsBold.arrowDown;
  }

  @override
  Widget build(BuildContext context) {
    return Icon(_arrow, size: size, color: color);
  }
}
