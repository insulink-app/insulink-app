import 'package:flutter/material.dart';

import '../profile/glucose/profile_glucose_state.dart';

/// Semantic glucose colours, shared across the app via the global [ThemeData]
/// so the profile range editors and the overview (headline value + chart) stay
/// in sync. Read with `Theme.of(context).extension<GlucoseColors>()!`.
@immutable
class GlucoseColors extends ThemeExtension<GlucoseColors> {
  const GlucoseColors({
    required this.inRange,
    required this.low,
    required this.high,
  });

  /// In target range (healthy green).
  final Color inRange;

  /// Below target / hypo (red).
  final Color low;

  /// Above target / hyper (amber).
  final Color high;

  /// A theme-independent palette for the one consumer without a theme: the
  /// Android home-screen widget, drawn by the launcher. Inside the app the
  /// per-theme instance built from `InsulinkColors` applies.
  static const standard = GlucoseColors(
    inRange: Color(0xFF2E9E5B),
    low: Color(0xFFE0533D),
    high: Color(0xFFE8A13A),
  );

  /// The colour for a single reading, by the user's target band.
  Color forValue(int mgdl, ProfileGlucoseState glucose) {
    if (mgdl < glucose.targetLow) {
      return low;
    }
    if (mgdl > glucose.targetHigh) {
      return high;
    }
    return inRange;
  }

  @override
  GlucoseColors copyWith({Color? inRange, Color? low, Color? high}) {
    return GlucoseColors(
      inRange: inRange ?? this.inRange,
      low: low ?? this.low,
      high: high ?? this.high,
    );
  }

  @override
  GlucoseColors lerp(ThemeExtension<GlucoseColors>? other, double t) {
    if (other is! GlucoseColors) {
      return this;
    }
    return GlucoseColors(
      inRange: Color.lerp(inRange, other.inRange, t)!,
      low: Color.lerp(low, other.low, t)!,
      high: Color.lerp(high, other.high, t)!,
    );
  }
}
