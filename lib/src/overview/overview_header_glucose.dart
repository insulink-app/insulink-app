import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/cgm/glucose_trend_icon.dart';
import 'package:insulink/src/overview/glucose_display_format.dart';
import 'package:insulink/src/overview/overview_data_view.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// The current value and trend arrow, small, in the overview's header.
///
/// It appears as the large value scrolls away under the header, driven by the
/// scroll position itself rather than switched on at a threshold: it fades in,
/// rises a few pixels and grows to full size exactly as fast as the finger
/// moves, and goes back the same way. The row is built once per reading; only
/// the opacity and transform change while scrolling.
class OverviewHeaderGlucose extends StatelessWidget {
  const OverviewHeaderGlucose({super.key});

  /// Scroll offsets between which it fades in: from when the large value starts
  /// to slide under the header until it has left.
  static const double _from = 40;
  static const double _to = 110;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final mgdl = controller.currentMgdl;
    if (mgdl == null) {
      return const SizedBox.shrink();
    }
    final value = _value(context, mgdl, controller);
    return ValueListenableBuilder<double>(
      valueListenable: overviewScrollOffset,
      child: value,
      builder: (context, offset, child) => _reveal(offset, child!),
    );
  }

  Widget _reveal(double offset, Widget child) {
    final linear = ((offset - _from) / (_to - _from)).clamp(0.0, 1.0);
    if (linear == 0) {
      return const SizedBox.shrink();
    }
    final shown = Curves.easeInOut.transform(linear);
    return IgnorePointer(
      child: Opacity(
        opacity: shown,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - shown)),
          child: Transform.scale(scale: 0.85 + 0.15 * shown, child: child),
        ),
      ),
    );
  }

  Widget _value(BuildContext context, int mgdl, CgmController controller) {
    final glucose = context.watch<ProfileGlucoseState>();
    final format = GlucoseDisplayFormat(glucose);
    final color = format.tone(
      context.insulinkColors,
      mgdl,
      stale: controller.currentIsStale,
    );
    final trend = controller.displayTrendPerMin;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Text(
          format.value(mgdl),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1,
            color: color,
          ),
        ),
        if (trend != null) _arrow(trend, color),
      ],
    );
  }

  Widget _arrow(double trend, Color color) {
    final direction = GlucoseTrendDirection.of(trend);
    return Transform.rotate(
      angle: direction.degrees * math.pi / 180,
      child: Icon(PhosphorIconsBold.arrowRight, size: 20, color: color),
    );
  }
}
