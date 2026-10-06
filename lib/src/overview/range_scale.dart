import 'package:flutter/material.dart';
import 'package:insulink/src/base/segment_bar.dart';
import 'package:insulink/src/overview/glucose_display_format.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:insulink/src/theme/insulink_text_styles.dart';
import 'package:provider/provider.dart';

/// Where the current value sits between low and high: a low / in range / high
/// bar from [floor] to [ceiling] mg/dL, split at the user's own target bounds,
/// with a knob on the value and the two bounds labelled underneath.
class RangeScale extends StatelessWidget {
  const RangeScale({super.key, required this.mgdl});

  /// The current value; null hides the knob.
  final int? mgdl;

  static const int floor = 40;
  static const int ceiling = 250;

  /// Horizontal position of [value] on the scale, 0..1, pinned to the ends.
  double fractionOf(int value) =>
      ((value - floor) / (ceiling - floor)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final glucose = context.watch<ProfileGlucoseState>();
    final colors = context.insulinkColors;
    return ExcludeSemantics(
      child: SizedBox(
        height: 44,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 13,
                child: _bar(glucose, colors),
              ),
              if (mgdl != null) _knob(constraints.maxWidth, glucose, colors),
              _label(constraints.maxWidth, glucose, glucose.targetLow, colors),
              _label(constraints.maxWidth, glucose, glucose.targetHigh, colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(ProfileGlucoseState glucose, InsulinkColors colors) {
    final low = (glucose.targetLow - floor).clamp(0, ceiling - floor);
    final high = (ceiling - glucose.targetHigh).clamp(0, ceiling - floor);
    final inRange = (ceiling - floor - low - high).clamp(0, ceiling - floor);
    return SegmentBar(
      height: 5,
      segments: [
        BarSegment(color: colors.low, weight: low.toDouble()),
        BarSegment(color: colors.range, weight: inRange.toDouble()),
        BarSegment(color: colors.high, weight: high.toDouble()),
      ],
    );
  }

  /// A 22 px knob in text colour with a 4 px ring in the page colour, and a
  /// 10 px core in the colour of the value's zone.
  Widget _knob(
    double width,
    ProfileGlucoseState glucose,
    InsulinkColors colors,
  ) {
    final value = mgdl!;
    final core = value < glucose.targetLow
        ? colors.low
        : value > glucose.targetHigh
        ? colors.high
        : colors.range;
    return Positioned(
      left: fractionOf(value) * width - 11,
      top: 4,
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.text,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: colors.ground, spreadRadius: 4)],
        ),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: core, shape: BoxShape.circle),
        ),
      ),
    );
  }

  Widget _label(
    double width,
    ProfileGlucoseState glucose,
    int bound,
    InsulinkColors colors,
  ) {
    return Positioned(
      left: fractionOf(bound) * width - 20,
      width: 40,
      top: 30,
      child: Text(
        GlucoseDisplayFormat(glucose).value(bound),
        textAlign: TextAlign.center,
        style: InsulinkTextStyles.axis.copyWith(color: colors.muted),
      ),
    );
  }
}
