import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/active_insulin_chart.dart';
import 'package:insulink/src/injection/active_insulin_sparkline.dart';
import 'package:insulink/src/theme/app_theme.dart';

/// Both charts read `points.first` and `points.last`. An empty list threw during
/// layout and left behind the grey box the failed render was sitting in, which
/// happens as soon as the insulin on board is made up ENTIRELY of pump insulin:
/// the curve comes from the meal log, so it is empty while the total is not.
void main() {
  final now = DateTime(2026, 5, 4, 21, 30);

  List<({DateTime at, double units})> points(int count) => [
        for (var index = 0; index < count; index++)
          (at: now.add(Duration(minutes: index * 5)), units: 1.0),
      ];

  /// The app's own theme, not a bare one: these charts read colour roles that
  /// only [AppTheme] registers, so a default theme fails on the render path this
  /// is meant to be exercising.
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SizedBox(height: 180, child: child)),
      ),
    );
  }

  group('a chart with nothing to draw draws nothing', () {
    testWidgets('the full chart survives an empty list', (tester) async {
      await pump(tester, ActiveInsulinChart(points: const [], now: now));

      expect(tester.takeException(), isNull);
    });

    /// One point is not a line either, and `_spanMin` would be zero.
    testWidgets('the full chart survives a single point', (tester) async {
      await pump(tester, ActiveInsulinChart(points: points(1), now: now));

      expect(tester.takeException(), isNull);
    });

    testWidgets('the sparkline survives an empty list', (tester) async {
      await pump(tester, ActiveInsulinSparkline(points: const [], now: now));

      expect(tester.takeException(), isNull);
    });
  });

  // The positive case is deliberately absent. A chart that DOES draw resolves a
  // localized axis label, and [Locales] is a singleton whose second rendering
  // test in a file returns nothing, so it would fail on the harness rather than
  // on the code. The three refusals above are the regression guard; the drawing
  // path is exercised by the app itself.
}
