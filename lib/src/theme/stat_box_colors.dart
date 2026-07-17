import 'package:flutter/material.dart';

/// The stat "boxes" ([SportSummaryTile]) keep the ORIGINAL brand indigo, held
/// apart from `colorScheme.primary`. The app's primary was later softened toward
/// a calmer blue-grey, but the boxes — and especially their icons — read best at
/// that first vivid indigo, so they carry their own tone here and do NOT follow
/// primary. Change primary freely; the boxes stay put.
///
/// [icon] is the glyph colour (drawn on the tinted face); [tintBase] is the
/// colour the panel / border / progress-fill tints are computed from — the box
/// twin of `BrandTints`, but on this fixed base rather than `primary`.
@immutable
class StatBoxColors extends ThemeExtension<StatBoxColors> {
  const StatBoxColors({required this.icon, required this.tintBase});

  final Color icon;
  final Color tintBase;

  Color get panel => tintBase.withValues(alpha: 0.08);
  Color get line => tintBase.withValues(alpha: 0.20);
  Color fill(double alpha) => tintBase.withValues(alpha: alpha);

  @override
  StatBoxColors copyWith({Color? icon, Color? tintBase}) => StatBoxColors(
    icon: icon ?? this.icon,
    tintBase: tintBase ?? this.tintBase,
  );

  @override
  StatBoxColors lerp(ThemeExtension<StatBoxColors>? other, double t) {
    if (other is! StatBoxColors) {
      return this;
    }
    return StatBoxColors(
      icon: Color.lerp(icon, other.icon, t)!,
      tintBase: Color.lerp(tintBase, other.tintBase, t)!,
    );
  }
}

extension StatBoxColorsContext on BuildContext {
  StatBoxColors get statBox => Theme.of(this).extension<StatBoxColors>()!;
}
