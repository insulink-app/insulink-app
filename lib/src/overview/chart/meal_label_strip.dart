import 'package:flutter/material.dart';
import 'package:insulink/src/overview/chart/chart_dashes.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One meal's label in the strip: where its line crosses the plot and what it
/// says ("30 g").
typedef MealLabel = ({double fraction, String text, int row});

/// The carb labels above the glucose chart: a small pill per meal, with the
/// meal's dashed line starting under it and running on through the glucose and
/// the insulin chart below. Labels of meals close together drop to a second row
/// ([MealLabelRows]) instead of covering each other.
class MealLabelStrip extends StatelessWidget {
  const MealLabelStrip({
    super.key,
    required this.labels,
    required this.stripWidth,
  });

  final List<MealLabel> labels;

  /// Width of the y label strip at the right, which the plot does not cover.
  final double stripWidth;

  static const double _pillHeight = 24;
  static const double _rowHeight = 30;

  /// How far a pill's centre keeps from the plot's ends, so a meal at the very
  /// edge of the window shows its whole label; its line stays where it is.
  static const double _edgeRoom = 32;

  /// Room for the pills plus a short run of line under the lowest one.
  double get height {
    final rows = labels.fold<int>(
      0,
      (most, label) => label.row > most ? label.row : most,
    );
    return (rows + 1) * _rowHeight + 10;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plotWidth = constraints.maxWidth - stripWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _StubPainter(
                    labels: labels,
                    plotWidth: plotWidth,
                    color: colors.muted.withValues(alpha: 0.35),
                    rowHeight: _rowHeight,
                  ),
                ),
              ),
              for (final label in labels)
                _pill(
                  colors,
                  label,
                  (label.fraction * plotWidth).clamp(
                    _edgeRoom,
                    plotWidth - _edgeRoom,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _pill(InsulinkColors colors, MealLabel label, double x) {
    return Positioned(
      top: label.row * _rowHeight,
      left: x,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: Container(
          height: _pillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.panelRaised,
            borderRadius: BorderRadius.circular(_pillHeight / 2),
          ),
          child: Text(
            label.text,
            style: InkText.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed line from under each pill down to the strip's bottom edge, where
/// the chart's own meal line takes over.
class _StubPainter extends CustomPainter {
  const _StubPainter({
    required this.labels,
    required this.plotWidth,
    required this.color,
    required this.rowHeight,
  });

  final List<MealLabel> labels;
  final double plotWidth;
  final Color color;
  final double rowHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (final label in labels) {
      final x = label.fraction * plotWidth;
      paintDashedLine(
        canvas,
        Offset(x, label.row * rowHeight + MealLabelStrip._pillHeight),
        Offset(x, size.height),
        paint,
        const [3, 4],
      );
    }
  }

  @override
  bool shouldRepaint(_StubPainter old) =>
      old.labels != labels || old.plotWidth != plotWidth || old.color != color;
}
