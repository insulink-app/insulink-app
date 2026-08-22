import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/overview/chart/chart_x_axis.dart';

/// The axis both charts are drawn on. Its whole job is that a moment maps to the
/// same fraction across the plot in each of them: get this wrong and a bar of
/// insulin sits beside the glucose it belongs to rather than under it, which is
/// the one thing a stacked pair must never do.
void main() {
  ChartXAxis axisOf({double range = 24, double rightEdge = 0.5}) => ChartXAxis(
        shift: 0.25,
        rangeHours: range,
        rightEdgeHours: rightEdge,
        anchor: DateTime(2026, 5, 4, 9),
      );

  test('the window is the range wide, ending at the right edge', () {
    final axis = axisOf();

    expect(axis.maxX, closeTo(0.75, 1e-9));
    expect(axis.maxX - axis.minX, closeTo(24, 1e-9));
  });

  test('the edges map to 0 and 1', () {
    final axis = axisOf();

    expect(axis.fractionOf(axis.minX), 0);
    expect(axis.fractionOf(axis.maxX), 1);
  });

  test('the middle maps to a half', () {
    final axis = axisOf();

    expect(axis.fractionOf((axis.minX + axis.maxX) / 2), closeTo(0.5, 1e-9));
  });

  /// Outside the window is clamped rather than extrapolated: a caller uses this
  /// to place something on the plot, and a fraction outside 0 to 1 would draw it
  /// into the axis strip or off the chart.
  test('outside the window is clamped', () {
    final axis = axisOf();

    expect(axis.fractionOf(axis.minX - 5), 0);
    expect(axis.fractionOf(axis.maxX + 5), 1);
  });

  test('a collapsed window maps everything to its start', () {
    final axis = axisOf(range: 0);

    expect(axis.fractionOf(10), 0);
  });

  /// Fewer ticks the wider the window, so the labels never crowd.
  test('the tick step widens with the window', () {
    expect(axisOf(range: 1).interval, 0.5);
    expect(axisOf(range: 4).interval, 2.0);
    expect(axisOf(range: 10).interval, 3.0);
    expect(axisOf(range: 24).interval, 6.0);
  });
}
