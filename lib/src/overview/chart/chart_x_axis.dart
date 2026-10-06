import 'package:flutter/widgets.dart';
import 'package:insulink/src/localization/locales.dart';

/// One label on the shared time axis, positioned as a fraction across the plot
/// so a chart can place it without knowing anything about session seconds.
class ChartTick {
  const ChartTick({required this.fraction, required this.label});

  /// 0 at the left edge of the plotting area, 1 at the right.
  final double fraction;

  final String label;
}

/// The time axis both charts are drawn on.
///
/// Pulled out of the glucose chart because the insulin chart underneath now
/// carries the labels: the pair reads as one picture with one axis, and an axis
/// that belongs to two charts cannot live inside either of them. The glucose
/// chart uses it to map values, the insulin chart to draw the labels, and both
/// get the same ticks by construction rather than by two implementations
/// happening to agree.
///
/// x is in hours relative to the latest reading, phase-shifted by [shift] so an
/// integer x lands on a full clock hour.
class ChartXAxis {
  const ChartXAxis({
    required this.shift,
    required this.rangeHours,
    required this.rightEdgeHours,
    required this.anchor,
  });

  final double shift;
  final double rangeHours;

  /// How far the right edge sits past the latest reading, which is where the
  /// forecast ends.
  final double rightEdgeHours;

  /// Wall-clock time at x == [shift], or null when there is no session clock to
  /// place the axis on.
  final DateTime? anchor;

  double get minX => shift + rightEdgeHours - rangeHours;

  double get maxX => shift + rightEdgeHours;

  /// Fewer ticks for wider windows so labels do not crowd; sub-hour steps once
  /// zoomed right in, so a tight window still gets a couple.
  double get interval {
    if (rangeHours <= 2) {
      return 0.5;
    }
    if (rangeHours <= 6) {
      return 2.0;
    }
    return rangeHours <= 12 ? 3.0 : 6.0;
  }

  /// Where an x sits across the plot: 0 at the left edge, 1 at the right.
  double fractionOf(double value) {
    final span = maxX - minX;
    return span <= 0 ? 0 : ((value - minX) / span).clamp(0.0, 1.0);
  }

  /// The labelled ticks inside the window, edges excluded.
  ///
  /// The fractional edge values are dropped rather than labelled: they move with
  /// every pixel of a pan, and a label that slides while its neighbours stand
  /// still reads as the chart glitching.
  List<ChartTick> ticks(BuildContext context) {
    final span = maxX - minX;
    if (span <= 0) {
      return const [];
    }
    final ticks = <ChartTick>[];
    final first = (minX / interval).floor() + 1;
    final last = (maxX / interval).ceil() - 1;
    for (var step = first; step <= last; step++) {
      final value = step * interval;
      if (value <= minX || value >= maxX) {
        continue;
      }
      ticks.add(
        ChartTick(
          fraction: (value - minX) / span,
          label: label(context, value),
        ),
      );
    }
    return ticks;
  }

  /// The clock time at [value] as "4:00", the overview preview's short form;
  /// an hours-ago offset when there is no anchor.
  String clockLabel(double value) {
    final start = anchor;
    if (start == null) {
      return '${value.toInt()}h';
    }
    final time = start.add(Duration(seconds: ((value - shift) * 3600).round()));
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// The clock time at [value], or an hours-ago offset when there is no anchor.
  ///
  /// A tick that lands off the hour (a deep zoom) shows its minutes too, so two
  /// ticks inside one hour do not read as the same label.
  String label(BuildContext context, double value) {
    final start = anchor;
    if (start == null) {
      return '${value.toInt()}h';
    }
    final time = start.add(Duration(seconds: ((value - shift) * 3600).round()));
    if (time.minute != 0) {
      return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }
    return Locales.string(
      context,
      'overview.chart.hour',
      params: ['${time.hour}'],
    );
  }
}
