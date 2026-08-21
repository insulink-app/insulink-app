import 'package:flutter/material.dart';
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

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - leftInset;
    if (plotWidth <= 0 || size.height <= 0) {
      return;
    }
    _paintGrid(canvas, size);
    _paintBasal(canvas, size, plotWidth);
    _paintBoluses(canvas, size, plotWidth);
    _paintScrub(canvas, size, plotWidth);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = gridWidth;
    for (var value = 0.0; value <= series.axisMax + 1e-9; value += series.axisStep) {
      final y = _yFor(value, size.height);
      _dashedLine(canvas, Offset(leftInset, y), Offset(size.width, y), paint,
          gridDash);
      _paintLabel(canvas, value, y);
    }
  }

  /// Basal as the hour it covers, so it reads as delivery that was running
  /// rather than an event at the top of the hour.
  ///
  /// An hour that only partly fits is drawn clipped, at its FULL height, because
  /// that is the rate the hour ran. Its cut side gets a square corner and no
  /// separating gap: a rounded corner says "the band ends here", and this one
  /// does not, it runs on past the edge of the window.
  void _paintBasal(Canvas canvas, Size size, double plotWidth) {
    final baseline = _yFor(0, size.height);
    for (final bar in series.bars.where((entry) => !entry.isBolus)) {
      final startsBefore = series.fractionOf(bar.at) <= 0;
      final endsAfter = series.fractionOf(bar.coversUntil) >= 1;
      final left = leftInset +
          series.fractionOf(bar.at) * plotWidth +
          (startsBefore ? 0 : 0.5);
      final right = leftInset +
          series.fractionOf(bar.coversUntil) * plotWidth -
          (endsAfter ? 0 : 0.5);
      final corner = const Radius.circular(2);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(
            left,
            _yFor(bar.units, size.height),
            right.clamp(left + 1, size.width),
            baseline,
          ),
          topLeft: startsBefore ? Radius.zero : corner,
          topRight: endsAfter ? Radius.zero : corner,
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
            _yFor(bar.units, size.height),
            centre + bolusWidth / 2,
            baseline,
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
    _dashedLine(canvas, Offset(x, 0), Offset(x, size.height), paint, scrubDash);
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

  /// Where a value sits vertically. A pixel is left at the bottom for the
  /// baseline itself, so the shortest bar is still a visible tick.
  double _yFor(double units, double height) {
    final usable = height - 2;
    return usable - (units / series.axisMax) * usable + 1;
  }

  void _dashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint,
    List<double> dash,
  ) {
    final total = (to - from).distance;
    if (total <= 0) {
      return;
    }
    final step = (to - from) / total;
    var drawn = 0.0;
    var on = true;
    while (drawn < total) {
      final length = (on ? dash[0] : dash[1]).clamp(0.0, total - drawn);
      if (on) {
        canvas.drawLine(
          from + step * drawn,
          from + step * (drawn + length),
          paint,
        );
      }
      drawn += length;
      on = !on;
    }
  }

  @override
  bool shouldRepaint(InsulinBarPainter old) {
    return old.series != series ||
        old.highlighted != highlighted ||
        old.scrubFraction != scrubFraction ||
        old.basal != basal ||
        old.bolus != bolus ||
        old.bolusWidth != bolusWidth;
  }
}
