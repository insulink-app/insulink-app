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

  /// The app's standard palette — the colours the profile range cards + chart
  /// use. Mid-tones tuned to read well on the small UI.
  static const standard = GlucoseColors(
    inRange: Color(0xFF2E9E5B),
    low: Color(0xFFE0533D),
    high: Color(0xFFE8A13A),
  );

  /// Palette for the big overview headline value, picked explicitly per theme.
  /// On light it is the chart's own green and red, so the number and the curve
  /// under it speak one colour family on the grey page; the deep forest green
  /// and brick red it used before looked heavy there. Only the amber is a shade
  /// deeper than [standard]'s, which at 2:1 against the page washes out even at
  /// headline size. All three hold at least 2.1:1 on `#F2F3F5`, enough for a
  /// number this large and bold…
  static const headlineLight = GlucoseColors(
    inRange: Color(0xFF2E9E5B),
    low: Color(0xFFE0533D),
    high: Color(0xFFE8952A),
  );

  /// …and brighter, vivid tones for the dark background (the red stays clearly
  /// RED here, not the light salmon the lightness shift produced).
  static const headlineDark = GlucoseColors(
    inRange: Color(0xFF39EF82),
    low: Color(0xFFFF453A),
    high: Color(0xFFFFB23E),
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
