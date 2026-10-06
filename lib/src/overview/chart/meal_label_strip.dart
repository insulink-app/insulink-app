import 'package:flutter/material.dart';
import 'package:insulink/src/overview/chart/meal_label_rows.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One meal's label: where its line crosses the plot and what it says ("30 g").
typedef MealLabel = ({double fraction, String text});

/// The carb labels at the top of the glucose chart, laid over the plot: a
/// small pill per meal on its dashed line, which the chart itself draws on
/// through the glucose and the insulin part.
///
/// Each pill is measured, and pills that would touch drop to a lower row
/// ([MealLabelRows]) instead of covering each other. A pill at the very edge of
/// the window moves in by just enough to show whole; its line stays put.
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
  static const double _padding = 9;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final style = InkText.caption.copyWith(
      fontWeight: FontWeight.w700,
      color: colors.text,
    );
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final plotWidth = constraints.maxWidth - stripWidth;
        final spans = [
          for (final label in labels)
            _span(label, plotWidth, _width(label.text, style, scaler)),
        ];
        final rows = const MealLabelRows().assign(spans);
        final lowest = rows.fold<int>(
          0,
          (most, row) => row > most ? row : most,
        );
        return SizedBox(
          height: lowest * _rowHeight + _pillHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var index = 0; index < labels.length; index++)
                Positioned(
                  top: rows[index] * _rowHeight,
                  left: spans[index].left,
                  child: _pill(colors, labels[index].text, style),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The pill's extent: centred on its line, but kept inside the plot.
  ({double left, double right}) _span(
    MealLabel label,
    double plotWidth,
    double width,
  ) {
    final half = width / 2;
    final centre = (label.fraction * plotWidth).clamp(
      half,
      (plotWidth - half).clamp(half, double.infinity),
    );
    return (left: centre - half, right: centre + half);
  }

  double _width(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    return painter.width + 2 * _padding;
  }

  Widget _pill(InsulinkColors colors, String text, TextStyle style) {
    return Container(
      height: _pillHeight,
      padding: const EdgeInsets.symmetric(horizontal: _padding),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.panelRaised,
        borderRadius: BorderRadius.circular(_pillHeight / 2),
      ),
      child: Text(text, style: style, maxLines: 1),
    );
  }
}
