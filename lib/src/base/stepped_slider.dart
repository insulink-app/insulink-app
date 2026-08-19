import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/theme/accent_colors.dart';

/// A slider that snaps to whole steps, ticks under the thumb, and shows no tick
/// marks.
///
/// The steps are real: a pod only accepts a temporary rate in whole percents of
/// its own grid and in half-hour slots, so a free-running slider would offer
/// values it would then have to round away. But Flutter draws a dot per division
/// ON TOP of the track, which at twenty divisions reads as speckle across the
/// selected range. The dots are hidden and the [HapticFeedback] takes their job:
/// the step is felt rather than seen, which is how the settings sliders already
/// behave.
class SteppedSlider extends StatelessWidget {
  const SteppedSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.steps,
    required this.onChanged,
  });

  /// The current value, in the same unit as [min] and [max].
  final double value;

  final double min;
  final double max;

  /// How many gaps there are between [min] and [max]: one fewer than the number
  /// of values the slider can rest on.
  final int steps;

  /// Called with the snapped value. Never with an intermediate one.
  final void Function(double value) onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: steps,
        activeColor: accent,
        inactiveColor: accent.withValues(alpha: 0.18),
        onChanged: _report,
      ),
    );
  }

  /// Ticks only when the value actually moved to a new step, so holding the thumb
  /// still inside one step stays quiet.
  void _report(double raw) {
    if (raw == value) {
      return;
    }
    HapticFeedback.selectionClick();
    onChanged(raw);
  }
}
