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
    required this.valueFraction,
    required this.dotColor,
    required this.value,
    required this.time,
    required this.rightInset,
  });

  /// Where the scrub sits across the plot, 0 at the left edge and 1 at the right.
  final double fraction;

  /// Where the reading sits vertically, 0 at the top of the plot and 1 at the
  /// bottom, so the dot lands on the curve.
  final double valueFraction;

  /// The reading's zone colour, or the neutral prediction grey past the last
  /// measured point. The same rule the chart's own touch dot follows.
  final Color dotColor;

  /// The headline, already formatted in the user's unit.
  final String value;

  final String time;

  /// The axis strip on the right, which is not part of the plotting area.
  final double rightInset;

  /// fl_chart's own tooltip geometry (its `LineTouchTooltipData` defaults), so
  /// the readout for a scrub below sits exactly where a touch here puts it:
  /// centred on the reading, its lower edge this far above the dot.
  static const double _margin = 16;
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 8,
  );
  static const double _maxContentWidth = 120;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final plotWidth = constraints.maxWidth - rightInset;
        final x = fraction * plotWidth;
        final dotY = valueFraction * constraints.maxHeight;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ScrubIndicator(
                  x: x,
                  valueFraction: valueFraction,
                  dotColor: dotColor,
                  line: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ),
            ),
            Positioned(
              left: x,
              top: dotY,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -1),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: _margin),
                  child: _pill(context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The same pill the chart's touch tooltip draws: inverse surface, value in
  /// bold over the time, centred.
  Widget _pill(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(
        maxWidth: _maxContentWidth + _padding.horizontal,
      ),
      padding: _padding,
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          text: value,
          style: TextStyle(
            color: scheme.onInverseSurface,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          children: [
            TextSpan(
              text: '\n$time',
              style: TextStyle(
                color: scheme.onInverseSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.normal,
                fontSize: 11,
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// The dot on the curve and the dashed line under it.
///
/// Copied from what fl_chart draws for a touch on this chart, down to where the
/// line stops: it runs from the bottom of the plot UP to the edge of the dot,
/// not across the whole picture. A mirrored readout that reached the top of the
/// chart is how somebody can tell the two halves apart, and the point of the
/// pair is that they cannot.
class _ScrubIndicator extends CustomPainter {
  const _ScrubIndicator({
    required this.x,
    required this.valueFraction,
    required this.dotColor,
    required this.line,
  });

  final double x;
  final double valueFraction;
  final Color dotColor;
  final Color line;

  static const double dotRadius = 4;
  static const double ringWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final dotY = valueFraction * size.height;
    paintDashedLine(
      canvas,
      Offset(x, size.height),
      Offset(x, dotY + dotRadius),
      Paint()
        ..color = line
        ..strokeWidth = ringWidth,
      const [4, 4],
    );
    canvas.drawCircle(
      Offset(x, dotY),
      dotRadius + ringWidth,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(Offset(x, dotY), dotRadius, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(_ScrubIndicator old) =>
      old.x != x ||
      old.valueFraction != valueFraction ||
      old.dotColor != dotColor ||
      old.line != line;
}
