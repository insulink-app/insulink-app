import 'package:flutter/material.dart';

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

  /// Palette for the big overview headline value, picked explicitly per theme
  /// (rather than nudging [standard]'s lightness, which washed colours toward
  /// grey/salmon). Deeper, saturated tones for the light background…
  static const headlineLight = GlucoseColors(
    inRange: Color(0xFF0F6B34),
    low: Color(0xFFC42108),
    high: Color(0xFFD07B01),
  );

  /// …and brighter, vivid tones for the dark background (the red stays clearly
  /// RED here, not the light salmon the lightness shift produced).
  static const headlineDark = GlucoseColors(
    inRange: Color(0xFF39EF82),
    low: Color(0xFFFF453A),
    high: Color(0xFFFFB23E),
  );

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
