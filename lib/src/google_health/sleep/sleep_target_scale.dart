import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/sleep_targets_state.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One sleep figure against its target: label and value on a line, and under it
/// a track with the target window tinted green and the value as a dot, green
/// inside the window and amber outside it.
///
/// The scale stretches to fit both the value and the target, so the window
/// always lands somewhere readable.
class SleepTargetScale extends StatelessWidget {
  const SleepTargetScale({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.target,
  });

  final String label;
  final String valueText;

  /// Null when the night has no value for it; the track is drawn without a dot.
  final int? value;

  final SleepTargetRange target;

  static const double _dot = 16;

  double get _scaleMax {
    final most = [value ?? 0, target.max, 1].reduce((a, b) => a > b ? a : b);
    return most * 1.3;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                style: InkText.body.copyWith(fontWeight: FontWeight.w400),
              ),
            ),
            Text(valueText, style: InkText.rowTitle),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 18,
          child: LayoutBuilder(
            builder: (context, constraints) =>
                _track(colors, constraints.maxWidth),
          ),
        ),
      ],
    );
  }

  Widget _track(InsulinkColors colors, double width) {
    final scale = _scaleMax;
    final dot = value;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _bar(0, width, colors.line),
        _bar(
          target.min / scale * width,
          (target.max - target.min) / scale * width,
          colors.range.withValues(alpha: 0.35),
        ),
        if (dot != null)
          Positioned(
            left: (dot / scale * width) - _dot / 2,
            top: 1,
            child: Container(
              width: _dot,
              height: _dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: target.contains(dot) ? colors.range : colors.high,
                boxShadow: [BoxShadow(color: colors.panel, spreadRadius: 3)],
              ),
            ),
          ),
      ],
    );
  }

  Widget _bar(double left, double width, Color color) {
    return Positioned(
      left: left,
      top: 6,
      width: width,
      height: 6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
