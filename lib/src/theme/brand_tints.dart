import 'package:flutter/material.dart';

/// The strengths at which the brand colour tints a surface.
///
/// These are computed from `primary`, not stored per theme, because that is what
/// a tint IS: the accent laid over whatever is beneath it. They only need names.
///
/// Nine different alphas were in use for these three ideas (0.06 / 0.08 / 0.10 /
/// 0.12 / 0.14 / 0.15 / 0.30 …), each guessed at its own call site. That is the
/// ground the badge problem grew on: with no shared value, "a faint tinted card"
/// meant something slightly different on every page, and the icon drawn on top
/// had nothing stable to contrast against.
///
/// Genuine SCALES are not tints and don't belong here — a progress fill that
/// brightens as it approaches its goal, or a button dimmed to half while
/// disabled. Those alphas carry information; these three only carry a role.
extension BrandTints on ColorScheme {
  /// A panel, card or chip washed with the brand colour.
  Color get tintPanel => primary.withValues(alpha: 0.08);

  /// The chosen row of a selection: enough to read as "this one", not enough to
  /// compete with a filled button.
  Color get tintSelected => primary.withValues(alpha: 0.14);

  /// A tinted rim, for a panel that should be outlined rather than only filled.
  Color get tintLine => primary.withValues(alpha: 0.20);
}
