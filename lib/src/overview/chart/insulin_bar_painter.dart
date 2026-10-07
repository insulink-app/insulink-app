import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
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
/// [axisInset] is the width of the axis strip on the left and must match the
/// glucose chart's `reservedSize` exactly, or the two plot areas start at
/// different x and every bar sits beside the glucose it belongs to rather than
/// under it. The plot is painted shifted right by it, so every x below is
/// measured from the plot's own left edge.
class InsulinBarPainter extends CustomPainter {
  const InsulinBarPainter({
    required this.series,
    required this.basal,
    required this.bolus,
    required this.labelColor,
    required this.scrubColor,
    required this.gridColor,
    required this.plotColor,
    required this.axisInset,
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

  /// The lines at each step of the unit scale, the top one being the shared
  /// edge with the glucose chart above.
  final Color gridColor;

  /// The plot's own face, so the insulin reads as the lower part of one chart.
  final Color plotColor;

  /// The axis label strip on the left, which is not part of the plot.
  final double axisInset;
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

  static const double gridWidth = 1;

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

  /// The baseline sits at the very top: it is the glucose chart's bottom edge,
  /// and the bars hang DOWN from it. The zero step carries no label, so
  /// nothing above it needs room.
  static const double topPad = 0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - axisInset;
    if (plotWidth <= 0 || size.height <= 0) {
      return;
    }
    canvas.save();
    canvas.translate(axisInset, 0);
    _paintFace(canvas, size, plotWidth);
    _paintGrid(canvas, size, plotWidth);
    _paintMeals(canvas, size, plotWidth);
    _paintBasal(canvas, size, plotWidth);
    _paintBoluses(canvas, size, plotWidth);
    _paintScrub(canvas, size, plotWidth);
    _paintTicks(canvas, size, plotWidth);
    canvas.restore();
  }

  void _paintFace(Canvas canvas, Size size, double plotWidth) {
    canvas.drawRect(
      Rect.fromLTRB(
        0,
        _yFor(0, size.height),
        plotWidth,
        _yFor(series.axisMax, size.height),
      ),
      Paint()..color = plotColor,
    );
  }

  /// A solid line at every step of the unit scale, labelled on the left; the
  /// zero line is the shared edge and goes unlabelled.
  void _paintGrid(Canvas canvas, Size size, double plotWidth) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = gridWidth;
    for (
      var value = 0.0;
      value <= series.axisMax + 1e-9;
      value += series.axisStep
    ) {
      final y = _yFor(value, size.height);
      canvas.drawLine(Offset(0, y), Offset(plotWidth, y), paint);
      if (value > 0) {
        _paintLabel(canvas, value, y, plotWidth);
      }
    }
  }

  /// The glucose chart's meal lines, continued through this one.
  void _paintMeals(Canvas canvas, Size size, double plotWidth) {
    final paint = Paint()
      ..color = mealColor.withValues(alpha: 0.35)
      ..strokeWidth = mealWidth;
    for (final fraction in mealFractions) {
      final x = fraction * plotWidth;
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
        text: TextSpan(text: tick.label, style: _labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final centre = tick.fraction * plotWidth;
      final left = (centre - text.width / 2).clamp(0.0, plotWidth - text.width);
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
          series.fractionOf(bar.at) * plotWidth + (startsBefore ? 0 : 0.5);
      final right =
          series.fractionOf(bar.coversUntil) * plotWidth -
          (endsAfter ? 0 : 0.5);
      final corner = const Radius.circular(2);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(
            left,
            baseline,
            right.clamp(left + 1, plotWidth),
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
      final centre = series.fractionOf(bar.at) * plotWidth;
      final paint = Paint()..color = bolus.withValues(alpha: _alphaFor(bar));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            centre - bolusWidth / 2,
            baseline,
            centre + bolusWidth / 2,
            _yFor(bar.units, size.height),
          ),
          Radius.circular(bolusWidth / 2),
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
    final x = fraction * plotWidth;
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

  void _paintLabel(Canvas canvas, double value, double y, double plotWidth) {
    final text = TextPainter(
      text: TextSpan(text: _format(value), style: _labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset(-axisInset, y - text.height / 2));
  }

  TextStyle get _labelStyle => InkText.caption.copyWith(color: labelColor);

  /// Whole units without decimals, a fraction with a German comma.
  String _format(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1).replaceFirst('.', ',');

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
        old.gridColor != gridColor ||
        old.plotColor != plotColor ||
        old.ticks != ticks ||
        old.mealFractions != mealFractions;
  }
}
