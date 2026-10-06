import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The glucose chart's y labels in the strip on its right: only the values
/// that mean something (the two target bounds and a reference line above
/// them), not a ruler of every 50.
///
/// Laid over the chart rather than handed to fl_chart, whose side titles can
/// only be placed on a fixed interval, and 70 or 180 sit on no interval a
/// readable axis would use.
class GlucoseYLabels extends StatelessWidget {
  const GlucoseYLabels({
    super.key,
    required this.values,
    required this.minY,
    required this.maxY,
    required this.stripWidth,
    required this.bottomInset,
    required this.format,
    this.leading = false,
  });

  /// In display units; values outside [minY]..[maxY] are left out.
  final List<double> values;
  final double minY;
  final double maxY;

  /// Width of the label strip at the right of the plot.
  final double stripWidth;

  /// Height under the plot that is not part of it (the x labels).
  final double bottomInset;

  final String Function(double value) format;

  /// The strip sits at the left of the plot instead of the right.
  final bool leading;

  static const double _lineHeight = 16;

  @override
  Widget build(BuildContext context) {
    final style = InkText.caption.copyWith(color: context.ink.muted);
    return LayoutBuilder(
      builder: (context, constraints) {
        final plotHeight = constraints.maxHeight - bottomInset;
        return Stack(
          children: [
            for (final value in values)
              if (value >= minY && value <= maxY && maxY > minY)
                Positioned(
                  left: leading ? 0 : null,
                  right: leading ? null : 0,
                  width: stripWidth,
                  top:
                      (maxY - value) / (maxY - minY) * plotHeight -
                      _lineHeight / 2,
                  height: _lineHeight,
                  child: Padding(
                    padding: EdgeInsets.only(left: leading ? 0 : 6),
                    child: Text(format(value), style: style, maxLines: 1),
                  ),
                ),
          ],
        );
      },
    );
  }
}
