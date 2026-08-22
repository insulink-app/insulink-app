import 'package:flutter/material.dart';
import 'package:insulink/src/overview/chart/chart_dashes.dart';

/// The readout a chart draws for a scrub that happened on the OTHER chart.
///
/// fl_chart cannot be asked to show one. `LineChart._withTouchedIndicators`
/// replaces both `showingTooltipIndicators` and every bar's `showingIndicators`
/// with its own touch state whenever `handleBuiltInTouches` is on, so a tooltip
/// set from outside is discarded before it is ever painted. Turning that
/// handling off to get it back would cost the chart the scrubbing it does well.
///
/// So the mirrored half is drawn over the top instead, in the same pill the
/// chart below uses. That is also what makes one finger look like one gesture
/// across the pair: both readouts are now the same widget, rather than one being
/// fl_chart's and the other ours.
class MirroredReadout extends StatelessWidget {
  const MirroredReadout({
    super.key,
    required this.fraction,
    required this.value,
    required this.time,
    required this.leftInset,
  });

  /// Where the scrub sits across the plot, 0 at the left edge and 1 at the right.
  final double fraction;

  /// The headline, already formatted in the user's unit.
  final String value;

  final String time;

  /// The axis strip on the left, which is not part of the plotting area.
  final double leftInset;

  static const double _width = 96;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final plotWidth = constraints.maxWidth - leftInset;
        final x = leftInset + fraction * plotWidth;
        final flip = x > constraints.maxWidth - _width - 8;
        return Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _ScrubLine(x, context))),
            Positioned(
              top: 0,
              left: flip ? null : x + 8,
              right: flip ? constraints.maxWidth - x + 8 : null,
              child: _pill(context),
            ),
          ],
        );
      },
    );
  }

  Widget _pill(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: _width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: scheme.onInverseSurface,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          Text(
            time,
            style: TextStyle(
              color: scheme.onInverseSurface.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// The dashed vertical under the scrub, matching the one fl_chart drops under a
/// finger on this chart and the one the chart below draws.
class _ScrubLine extends CustomPainter {
  _ScrubLine(this.x, BuildContext context)
      : color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35);

  final double x;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    paintDashedLine(
      canvas,
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 1.5,
      const [4, 4],
    );
  }

  @override
  bool shouldRepaint(_ScrubLine old) => old.x != x || old.color != color;
}
