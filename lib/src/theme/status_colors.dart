import 'package:flutter/material.dart';

/// Danger and warning as drawn ON a surface — the status tones the app needs and
/// [ColorScheme] has no honest role for.
///
/// Two gaps are filled here:
///
/// - **`danger`** is not `colorScheme.error`. `error` is tuned as a FILL (the red
///   confirm button of a delete, the notification badge), which pins it to a mid
///   tone that only reaches ~4:1 as a label on the dark surface — the same trap
///   `primary` falls into, see [AccentColors]. `danger` is the light tone for
///   error TEXT: an expired sensor, a failed connect, the "stop sensor" label.
/// - **`warning`** has no `ColorScheme` role at all. Amber sits between "fine"
///   and "wrong": a reading that is overdue, a sensor inside its grace period.
/// - **`positive`** has none either: a confirmed action, a weight trending down.
///
/// All three are per theme, which is the whole point: the hard-coded
/// `Colors.redAccent` / `Colors.orangeAccent` / `Colors.green` these replaced
/// could not be — `orangeAccent` on the light page measured ~1.9:1, i.e. all but
/// invisible.
///
/// This is deliberately NOT [GlucoseColors]. That extension is the language of
/// glucose (in range / low / high) and is read by the chart and the readouts; a
/// delete button borrowing its red would tie two unrelated meanings together.
///
/// Read with `context.danger` / `context.warning` / `context.positive`.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.danger,
    required this.warning,
    required this.positive,
  });

  /// Error as a foreground: legible against this theme's surfaces.
  final Color danger;

  /// Amber for a state that is off-nominal but not an error.
  final Color warning;

  /// Green: went well, or moving the right way.
  final Color positive;

  @override
  StatusColors copyWith({Color? danger, Color? warning, Color? positive}) {
    return StatusColors(
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      positive: positive ?? this.positive,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) {
      return this;
    }
    return StatusColors(
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
    );
  }
}

/// Terse access at the call sites, mirroring `context.accent`.
extension StatusColorsContext on BuildContext {
  StatusColors get _status => Theme.of(this).extension<StatusColors>()!;

  /// Error as a foreground — for error TEXT, not for a red fill (that is
  /// `colorScheme.error`).
  Color get danger => _status.danger;

  /// Amber: off-nominal, but not an error.
  Color get warning => _status.warning;

  /// Green: went well, or moving the right way.
  Color get positive => _status.positive;
}
