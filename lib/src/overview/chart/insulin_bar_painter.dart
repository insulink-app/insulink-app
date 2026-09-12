import 'package:flutter/material.dart';
import 'package:insulink/src/overview/chart/chart_dashes.dart';
import 'package:insulink/src/overview/chart/chart_x_axis.dart';
import 'package:insulink/src/overview/chart/insulin_chart_series.dart';

/// Draws the insulin at its real position in time, in the glucose chart's visual
/// language.
///
/// Hand-painted rather than handed to the chart library, and that is the point.
/// `BarChart` lays its groups out in the order they are given and spaces them
/// evenly; the `x` on a group is a label, not a position. Bars drawn that way sit
/// at even intervals no matter when the insulin went in, so a chart claiming to
/// share the glucose chart's time axis would be showing something else.
///
/// **The two kinds are drawn as different shapes, not just different colours.**
/// Basal is an hour the pump spent delivering, so it covers that hour: a band as
/// wide as the hour is long. A bolus is a moment, so it is a narrow bar standing
/// in front of the band. That answers what happens when the two coincide, which
/// they usually do: a bolus lands inside an hour that also ran basal, and the bar
/// stands ON the band it happened during rather than colliding with it or hiding
/// it. Two equal bars fighting for the same pixels could only ever be read wrong.
///
/// [leftInset] is the width of the axis strip and must match the glucose chart's
/// `reservedSize` exactly, or the two plot areas start at different x and every
/// bar sits beside the glucose it belongs to rather than under it.
class InsulinBarPainter extends CustomPainter {
  const InsulinBarPainter({
    required this.series,
    required this.basal,
    required this.bolus,
    required this.labelColor,
    required this.scrubColor,
    required this.leftInset,
    required this.bolusWidth,
    required this.mealColor,
    this.ticks = const [],
    this.mealFractions = const [],
    this.scrubFraction,
    this.highlighted,
  });

  final InsulinChartSeries series;
  final Color basal;
  final Color bolus;
  final Color labelColor;
  final Color scrubColor;
  final double leftInset;
  final double bolusWidth;
  final Color mealColor;

  /// The shared axis' labels, drawn under THIS chart because it is the lower of
  /// the pair. See [ChartXAxis].
  final List<ChartTick> ticks;

  /// Where the glucose chart's meal lines cross, so each runs through both
  /// charts instead of stopping at the border between them.
  final List<double> mealFractions;

  /// Where the pointer is across the window, for the scrub line.
  final double? scrubFraction;

  /// The bar under the pointer, kept full strength while the rest dim.
  final InsulinBar? highlighted;

  /// The gridlines fl_chart draws by default, which is what the glucose chart
  /// above uses. Copied rather than invented so the two read as one chart.
  static const Color gridColor = Colors.blueGrey;
  static const double gridWidth = 0.4;
  static const List<double> gridDash = [8, 4];

  /// The scrub line the glucose chart draws while a finger is on it.
  static const double scrubWidth = 1.5;
  static const List<double> scrubDash = [4, 4];

  /// The meal marker, matching the glucose chart's dashes exactly: the line is
  /// one line, and two halves drawn differently would give that away.
  static const double mealWidth = 1.5;
  static const List<double> mealDash = [3, 4];

  /// Room under the plot for the axis labels, the same strip fl_chart reserves
  /// for them on the chart above.
  static const double bottomInset = 24;

  /// Room above the baseline so the topmost axis label is not cut off by the
  /// edge. The bars hang DOWN from that baseline, so nothing else needs it.
  static const double topPad = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - leftInset;
    if (plotWidth <= 0 || size.height <= 0) {
      return;
    }
    _paintGrid(canvas, size);
    _paintMeals(canvas, size, plotWidth);
    _paintBasal(canvas, size, plotWidth);
    _paintBoluses(canvas, size, plotWidth);
    _paintScrub(canvas, size, plotWidth);
    _paintTicks(canvas, size, plotWidth);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = gridWidth;
    for (
      var value = 0.0;
      value <= series.axisMax + 1e-9;
      value += series.axisStep
    ) {
      final y = _yFor(value, size.height);
      paintDashedLine(
        canvas,
        Offset(leftInset, y),
        Offset(size.width, y),
        paint,
        gridDash,
      );
      _paintLabel(canvas, value, y);
    }
  }

  /// The glucose chart's meal lines, continued through this one.
  void _paintMeals(Canvas canvas, Size size, double plotWidth) {
    final paint = Paint()
      ..color = mealColor.withValues(alpha: 0.35)
      ..strokeWidth = mealWidth;
    for (final fraction in mealFractions) {
      final x = leftInset + fraction * plotWidth;
      paintDashedLine(
        canvas,
        Offset(x, 0),
        Offset(x, size.height - bottomInset),
        paint,
        mealDash,
      );
    }
  }

  /// The shared axis' labels, centred on their tick and kept inside the plot at
  /// both ends so the first and last are not clipped to half a time.
  void _paintTicks(Canvas canvas, Size size, double plotWidth) {
    for (final tick in ticks) {
      final text = TextPainter(
        text: TextSpan(
          text: tick.label,
          style: TextStyle(fontSize: 10, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final centre = leftInset + tick.fraction * plotWidth;
      final left = (centre - text.width / 2).clamp(
        leftInset,
        size.width - text.width,
      );
      text.paint(canvas, Offset(left, size.height - bottomInset + 6));
    }
  }

  /// Basal as the hour it covers, so it reads as delivery that was running
  /// rather than an event at the top of the hour.
  ///
  /// Hangs DOWN from a baseline at the top, mirroring the glucose line above it.
  /// Insulin is the thing that pulls glucose down, and a chart of it growing
  /// upward towards the curve it opposes reads as the two agreeing. Hung the
  /// other way the pair shares one edge and the taller the bar, the further it
  /// reaches from the line it acted on.
  ///
  /// An hour that only partly fits is drawn clipped, at its FULL length, because
  /// that is the rate the hour ran. Its cut side gets a square corner and no
  /// separating gap: a rounded corner says "the band ends here", and this one
  /// does not, it runs on past the edge of the window.
  void _paintBasal(Canvas canvas, Size size, double plotWidth) {
    final baseline = _yFor(0, size.height);
    for (final bar in series.bars.where((entry) => !entry.isBolus)) {
      final startsBefore = series.fractionOf(bar.at) <= 0;
      final endsAfter = series.fractionOf(bar.coversUntil) >= 1;
      final left =
          leftInset +
          series.fractionOf(bar.at) * plotWidth +
          (startsBefore ? 0 : 0.5);
      final right =
          leftInset +
          series.fractionOf(bar.coversUntil) * plotWidth -
          (endsAfter ? 0 : 0.5);
      final corner = const Radius.circular(2);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(
            left,
            baseline,
            right.clamp(left + 1, size.width),
            _yFor(bar.units, size.height),
          ),
          bottomLeft: startsBefore ? Radius.zero : corner,
          bottomRight: endsAfter ? Radius.zero : corner,
        ),
        Paint()..color = basal.withValues(alpha: _alphaFor(bar)),
      );
    }
  }

  /// Boluses last, so a dose is never hidden behind the hour it happened in.
  void _paintBoluses(Canvas canvas, Size size, double plotWidth) {
    final baseline = _yFor(0, size.height);
    for (final bar in series.bars.where((entry) => entry.isBolus)) {
      final centre = leftInset + series.fractionOf(bar.at) * plotWidth;
      final paint = Paint()..color = bolus.withValues(alpha: _alphaFor(bar));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            centre - bolusWidth / 2,
            baseline,
            centre + bolusWidth / 2,
            _yFor(bar.units, size.height),
          ),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  double _alphaFor(InsulinBar bar) =>
      highlighted == null || highlighted == bar ? 1 : 0.3;

  /// The same dashed vertical the glucose chart drops under a scrubbing finger,
  /// so one gesture across the pair looks like one gesture.
  void _paintScrub(Canvas canvas, Size size, double plotWidth) {
    final fraction = scrubFraction;
    if (fraction == null) {
      return;
    }
    final x = leftInset + fraction * plotWidth;
    final paint = Paint()
      ..color = scrubColor
      ..strokeWidth = scrubWidth;
    paintDashedLine(
      canvas,
      Offset(x, 0),
      Offset(x, size.height - bottomInset),
      paint,
      scrubDash,
    );
  }

  void _paintLabel(Canvas canvas, double value, double y) {
    final text = TextPainter(
      text: TextSpan(
        text: _format(value),
        style: TextStyle(fontSize: 10, color: labelColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset(leftInset - text.width - 4, y - text.height / 2));
  }

  String _format(double value) =>
      value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

  /// Where a value sits vertically, measured DOWN from the baseline at the top.
  ///
  /// A pixel is left below the baseline itself, so the shortest bar is still a
  /// visible tick rather than nothing at all.
  double _yFor(double units, double height) {
    final usable = height - bottomInset - topPad - 2;
    return topPad + (units / series.axisMax) * usable + 1;
  }

  @override
  bool shouldRepaint(InsulinBarPainter old) {
    return old.series != series ||
        old.highlighted != highlighted ||
        old.scrubFraction != scrubFraction ||
        old.basal != basal ||
        old.bolus != bolus ||
        old.bolusWidth != bolusWidth ||
        old.ticks != ticks ||
        old.mealFractions != mealFractions;
  }
}
