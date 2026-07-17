import 'package:flutter/material.dart';

/// The brand accent as drawn ON a surface — icons, glyphs and labels that sit on
/// the page rather than filling a shape.
///
/// This is deliberately NOT `ColorScheme.primary`. That colour is tuned as a
/// FILL, with white text on top, which pins it to a mid tone. On a dark surface
/// the same mid tone only reaches ~4:1 as a foreground, and the icons drawn at
/// reduced alpha on faint primary-tinted chips fall under 3:1. A fill colour and
/// a foreground colour pull in opposite directions on dark, so they are two
/// values here. On light they are the same colour — a deep indigo on a near-white
/// page is legible either way.
///
/// Read with `Theme.of(context).extension<AccentColors>()!`.
@immutable
class AccentColors extends ThemeExtension<AccentColors> {
  const AccentColors({required this.onSurface});

  /// The accent tone legible against this theme's surfaces.
  final Color onSurface;

  @override
  AccentColors copyWith({Color? onSurface}) {
    return AccentColors(onSurface: onSurface ?? this.onSurface);
  }

  @override
  AccentColors lerp(ThemeExtension<AccentColors>? other, double t) {
    if (other is! AccentColors) {
      return this;
    }
    return AccentColors(onSurface: Color.lerp(onSurface, other.onSurface, t)!);
  }
}

/// Terse access to the accent at the call sites that draw with it. Most of them
/// are icons inside small helper widgets, where a full
/// `Theme.of(context).extension<AccentColors>()!.onSurface` per line would bury
/// the widget it is colouring.
extension AccentColorsContext on BuildContext {
  Color get accent => Theme.of(this).extension<AccentColors>()!.onSurface;
}
