import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// A per-minute glucose trend, in the 5 directional buckets every readout uses,
/// so the overview headline, the workout vitals bar and the trend words can
/// never drift apart on what "rising" means.
enum GlucoseTrendDirection {
  risingFast(PhosphorIconsBold.arrowUp, -90, 'rising_fast'),
  rising(PhosphorIconsBold.arrowUpRight, -45, 'rising'),
  stable(PhosphorIconsBold.arrowRight, 0, 'stable'),
  falling(PhosphorIconsBold.arrowDownRight, 45, 'falling'),
  fallingFast(PhosphorIconsBold.arrowDown, 90, 'falling_fast');

  const GlucoseTrendDirection(this.icon, this.degrees, this.slug);

  /// The bucket for a trend in mg/dL per minute.
  factory GlucoseTrendDirection.of(double perMin) {
    if (perMin >= 2) {
      return risingFast;
    }
    if (perMin >= 1) {
      return rising;
    }
    if (perMin > -1) {
      return stable;
    }
    if (perMin > -2) {
      return falling;
    }
    return fallingFast;
  }

  final IconData icon;

  /// Clockwise rotation of a right-pointing arrow that shows this trend.
  final double degrees;

  /// Key suffix under `overview.trend`.
  final String slug;
}

/// Phosphor arrow for a per-minute glucose trend.
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

  @override
  Widget build(BuildContext context) {
    return Icon(
      GlucoseTrendDirection.of(perMin).icon,
      size: size,
      color: color,
    );
  }
}
