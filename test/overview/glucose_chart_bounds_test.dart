import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/overview/chart/glucose_chart_bounds.dart';

/// The vertical span a glucose chart is drawn over.
///
/// A fixed 0 to 300 spends most of the picture on ranges nobody reaches, which
/// is the empty band above and below the curve on the detail page. Both charts
/// now fit the axis to the readings, and both do it the same way, which is the
/// point of this living in one place.
void main() {
  test('an ordinary day starts at 50, not at 0', () {
    const bounds = GlucoseChartBounds([90, 120, 160]);

    expect(bounds.minMgdl, 50);
  });

  test('a low reading pulls the floor down to the next fifty', () {
    const bounds = GlucoseChartBounds([42, 120]);

    expect(bounds.minMgdl, 0);
  });

  test('a hypo just under a boundary still fits inside', () {
    const bounds = GlucoseChartBounds([51, 120]);

    expect(bounds.minMgdl, 50);
  });

  /// A flat day still has to show where the high range begins, so the top never
  /// drops below 200 however calm the readings are.
  test('a calm day still reaches 200', () {
    const bounds = GlucoseChartBounds([90, 100, 110]);

    expect(bounds.maxMgdl, 200);
  });

  test('the peak gets headroom above it', () {
    const bounds = GlucoseChartBounds([90, 245]);

    expect(bounds.maxMgdl, 300);
    expect(bounds.maxMgdl, greaterThan(245));
  });

  /// Rounding outwards is what stops the whole chart rescaling when one reading
  /// moves a few points.
  test('a small change does not move the axis', () {
    const before = GlucoseChartBounds([90, 210]);
    const after = GlucoseChartBounds([90, 215]);

    expect(after.maxMgdl, before.maxMgdl);
  });

  test('no readings fall back to a sane window', () {
    const bounds = GlucoseChartBounds([]);

    expect(bounds.minMgdl, 50);
    expect(bounds.maxMgdl, 200);
  });
}
