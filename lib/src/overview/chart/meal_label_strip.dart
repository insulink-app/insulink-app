import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One meal's label in the strip: where its line crosses the plot and what it
/// says ("30 g").
typedef MealLabel = ({double fraction, String text, int row});

/// The carb labels at the top of the glucose chart, laid over the plot: a
/// small pill per meal on its dashed line, which the chart itself draws on
/// through the glucose and the insulin part. Labels of meals close together
/// drop to a second row ([MealLabelRows]) instead of covering each other.
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

  /// Room for the pills, one row per stacking level.
  double get height {
    final rows = labels.fold<int>(
      0,
      (most, label) => label.row > most ? label.row : most,
    );
    return rows * _rowHeight + _pillHeight;
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
