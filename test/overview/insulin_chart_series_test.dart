import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/overview/chart/insulin_chart_series.dart';
import 'package:insulink/src/pump/pod_store.dart';

void main() {
  final from = DateTime(2026, 5, 4, 8);
  final to = DateTime(2026, 5, 4, 12);

  Meal bolusAt(DateTime time, double units) => Meal(
        time: time,
        carbs: 0,
        glucoseMgdl: 0,
        bolus: units,
        entries: const [],
      );

  PodBasalHour basalAt(DateTime hour, double units) =>
      PodBasalHour(hour: hour, units: units);

  InsulinChartSeries seriesOf({
    List<PodBasalHour> basal = const [],
    List<Meal> meals = const [],
  }) =>
      InsulinChartSeries(basalHours: basal, meals: meals, from: from, to: to);

  group('only what falls inside the window is drawn', () {
    test('bars outside it are left out', () {
      final series = seriesOf(
        basal: [
          basalAt(DateTime(2026, 5, 4, 7), 1.0),
          basalAt(DateTime(2026, 5, 4, 9), 1.0),
          basalAt(DateTime(2026, 5, 4, 13), 1.0),
        ],
        meals: [
          bolusAt(DateTime(2026, 5, 4, 6), 4),
          bolusAt(DateTime(2026, 5, 4, 10), 4),
        ],
      );

      expect(series.bars, hasLength(2));
      expect(series.basalUnits, 1.0);
      expect(series.bolusUnits, 4.0);
    });

    /// The start counts and the end does not, so a bar on the boundary belongs
    /// to exactly one window rather than being drawn twice as the user pans.
    test('a bolus on the start is inside, one on the end is not', () {
      final series = seriesOf(
        meals: [bolusAt(from, 4), bolusAt(to, 4)],
      );

      expect(series.bars.single.at, from);
    });
  });

  /// An hour of basal is a stretch, not a moment, so it belongs on screen
  /// whenever any part of it does.
  group('an hour of basal that only partly fits', () {
    /// The reported bug: a window opening mid-hour dropped that hour entirely,
    /// and a band the user could see the rest of vanished at the left edge.
    test('an hour that started before the window is still drawn', () {
      final series = InsulinChartSeries(
        basalHours: [basalAt(DateTime(2026, 5, 4, 7, 30), 1.0)],
        meals: const [],
        from: DateTime(2026, 5, 4, 8),
        to: DateTime(2026, 5, 4, 12),
      );

      expect(series.bars, hasLength(1));
    });

    test('an hour that runs past the window is still drawn', () {
      final series = seriesOf(
        basal: [basalAt(DateTime(2026, 5, 4, 11, 30), 1.0)],
      );

      expect(series.bars, hasLength(1));
    });

    /// Touching the edge is not overlapping: an hour ending exactly where the
    /// window begins has nothing inside it to draw.
    test('an hour that only touches the edge is left out', () {
      final series = seriesOf(
        basal: [
          basalAt(from.subtract(const Duration(hours: 1)), 1.0),
          basalAt(to, 1.0),
        ],
      );

      expect(series.bars, isEmpty);
    });

    /// The band is drawn at its full height, because that is the rate the hour
    /// ran. The legend answers a different question, so it counts the share of
    /// the hour that is actually on screen. Within an hour the pump runs one
    /// rate, so pro rata is exact rather than an approximation.
    test('the legend counts only the share that is on screen', () {
      final series = InsulinChartSeries(
        basalHours: [basalAt(DateTime(2026, 5, 4, 7, 30), 1.0)],
        meals: const [],
        from: DateTime(2026, 5, 4, 8),
        to: DateTime(2026, 5, 4, 12),
      );

      expect(series.bars.single.units, 1.0);
      expect(series.basalUnits, closeTo(0.5, 1e-9));
    });

    test('an hour fully inside counts in full', () {
      final series = seriesOf(basal: [basalAt(DateTime(2026, 5, 4, 9), 1.2)]);

      expect(series.basalUnits, closeTo(1.2, 1e-9));
    });

    /// A dose is a moment, so it is in or out and never counted in fractions.
    test('a bolus is never pro-rated', () {
      final series = seriesOf(meals: [bolusAt(DateTime(2026, 5, 4, 11, 59), 6)]);

      expect(series.bolusUnits, closeTo(6, 1e-9));
    });
  });

  group('the two kinds stay apart', () {
    /// They are different things: basal is a rate the pump ran for an hour, a
    /// bolus is a dose given at a moment. One total would hide the only
    /// distinction the chart exists to draw.
    test('basal and bolus are never summed', () {
      final series = seriesOf(
        basal: [basalAt(DateTime(2026, 5, 4, 9), 1.2)],
        meals: [bolusAt(DateTime(2026, 5, 4, 9, 30), 6)],
      );

      expect(series.basalUnits, closeTo(1.2, 1e-9));
      expect(series.bolusUnits, closeTo(6, 1e-9));
      expect(series.bars.map((bar) => bar.isBolus), [false, true]);
    });

    test('bars are ordered by time, whichever kind they are', () {
      final series = seriesOf(
        basal: [
          basalAt(DateTime(2026, 5, 4, 11), 1.0),
          basalAt(DateTime(2026, 5, 4, 9), 1.0),
        ],
        meals: [bolusAt(DateTime(2026, 5, 4, 10), 4)],
      );

      expect(
        series.bars.map((bar) => bar.at.hour),
        [9, 10, 11],
      );
    });

    /// A meal logged without insulin, and an hour the pod delivered nothing,
    /// would both draw a bar of zero height that reads as a missing value.
    test('nothing is drawn for zero units', () {
      final series = seriesOf(
        basal: [basalAt(DateTime(2026, 5, 4, 9), 0)],
        meals: [bolusAt(DateTime(2026, 5, 4, 10), 0)],
      );

      expect(series.bars, isEmpty);
      expect(series.isEmpty, isTrue);
    });
  });

  /// The usual case, not an edge case: a bolus almost always lands inside an
  /// hour that was also running basal.
  group('a bolus given during an hour of basal', () {
    final hour = DateTime(2026, 5, 4, 9);
    final series = InsulinChartSeries(
      basalHours: [PodBasalHour(hour: hour, units: 1.1)],
      meals: [
        Meal(
          time: hour.add(const Duration(minutes: 20)),
          carbs: 0,
          glucoseMgdl: 0,
          bolus: 5,
          entries: const [],
        ),
      ],
      from: DateTime(2026, 5, 4, 8),
      to: DateTime(2026, 5, 4, 12),
    );

    /// Neither swallows the other. They are drawn as different shapes, the
    /// basal as the hour it covers and the bolus as a bar standing in front of
    /// it, so the dose reads as having happened DURING that hour.
    test('both are kept, and stay their own kind', () {
      expect(series.bars, hasLength(2));
      expect(series.basalUnits, closeTo(1.1, 1e-9));
      expect(series.bolusUnits, closeTo(5, 1e-9));
    });

    /// Basal covers its hour; a bolus is a moment and ends where it starts.
    test('only basal covers a stretch of time', () {
      final basal = series.bars.firstWhere((bar) => !bar.isBolus);
      final bolus = series.bars.firstWhere((bar) => bar.isBolus);

      expect(basal.coversUntil, hour.add(const Duration(hours: 1)));
      expect(bolus.coversUntil, bolus.at);
    });

    /// The two are hit differently because they are different shapes: the band
    /// covers its hour, the spike has a reach around itself.
    test('pointing at the dose picks the bolus', () {
      final atDose = hour.add(const Duration(minutes: 20));

      expect(series.nearest(series.fractionOf(atDose))!.isBolus, isTrue);
    });

    /// The one that caught a real mistake: measuring to the START of the basal
    /// bar made a point late in the hour nearer the bolus than the hour it is
    /// plainly inside.
    test('pointing into the hour away from the dose picks the basal', () {
      for (final minute in [2, 40, 55, 59]) {
        final inside = hour.add(Duration(minutes: minute));

        expect(series.nearest(series.fractionOf(inside))!.isBolus, isFalse,
            reason: 'minute $minute is inside the basal hour');
      }
    });

    test('a dose at the top of the hour is still selectable', () {
      final together = InsulinChartSeries(
        basalHours: [PodBasalHour(hour: hour, units: 1.1)],
        meals: [
          Meal(
            time: hour,
            carbs: 0,
            glucoseMgdl: 0,
            bolus: 5,
            entries: const [],
          ),
        ],
        from: DateTime(2026, 5, 4, 8),
        to: DateTime(2026, 5, 4, 12),
      );

      expect(together.nearest(together.fractionOf(hour))!.isBolus, isTrue);
    });
  });

  /// The window reaches past the last reading so the glucose chart can show its
  /// forecast. A chart of things that have HAPPENED must stop where the measured
  /// data does, or the hour in progress is drawn across time that has not
  /// occurred yet.
  group('the hour in progress stops at the live edge', () {
    final hour = DateTime(2026, 5, 4, 11);
    final edge = DateTime(2026, 5, 4, 11, 20);

    InsulinChartSeries running({DateTime? liveEdge}) => InsulinChartSeries(
          basalHours: [basalAt(hour, 0.4)],
          meals: const [],
          from: from,
          to: DateTime(2026, 5, 4, 12, 30),
          liveEdge: liveEdge,
        );

    test('the band is cut there instead of running the full hour', () {
      expect(running(liveEdge: edge).bars.single.coversUntil, edge);
    });

    test('a finished hour keeps its full length', () {
      final series = InsulinChartSeries(
        basalHours: [basalAt(DateTime(2026, 5, 4, 9), 1.1)],
        meals: const [],
        from: from,
        to: to,
        liveEdge: DateTime(2026, 5, 4, 11, 20),
      );

      expect(series.bars.single.coversUntil, DateTime(2026, 5, 4, 10));
    });

    /// Without a sensor session there is no live edge to place, and an hour that
    /// is simply drawn in full is better than one cut at a guess.
    test('no live edge leaves every hour at its full length', () {
      expect(running().bars.single.coversUntil,
          hour.add(const Duration(hours: 1)));
    });

    /// The ledger books the running hour as it goes, so its units are already
    /// only what has been delivered. The band is short because the hour is
    /// short, not because anything is being scaled twice.
    test('the running hour counts what it actually delivered', () {
      expect(running(liveEdge: edge).basalUnits, closeTo(0.4, 1e-9));
    });

    /// An edge landing exactly on the start of an hour leaves nothing of it to
    /// draw, and must not produce a band running backwards.
    test('an edge at the top of the hour never inverts the band', () {
      final series = InsulinChartSeries(
        basalHours: [basalAt(hour, 0.4)],
        meals: const [],
        from: from,
        to: to,
        liveEdge: hour,
      );

      for (final bar in series.bars) {
        expect(bar.coversUntil.isBefore(bar.at), isFalse);
      }
    });
  });

  group('the axis', () {
    test('is set by the tallest bar', () {
      final series = seriesOf(
        basal: [basalAt(DateTime(2026, 5, 4, 9), 1.0)],
        meals: [bolusAt(DateTime(2026, 5, 4, 10), 6.5)],
      );

      expect(series.maxUnits, closeTo(6.5, 1e-9));
    });

    /// An empty window still needs a scale, or the chart collapses to a line.
    test('never collapses to zero', () {
      expect(seriesOf().maxUnits, 1);
    });

    /// Round numbers, because the reader judges a bar against the gridlines at a
    /// glance. Lines at 2.4 and 4.8 units cannot be measured against.
    test('the gridlines land on round numbers', () {
      final cases = <double, (double, double)>{
        0.4: (0.5, 0.5),
        1.2: (0.5, 1.5),
        3.0: (1.0, 3.0),
        6.5: (2.0, 8.0),
        12.0: (5.0, 15.0),
      };

      for (final entry in cases.entries) {
        final series = seriesOf(
          meals: [bolusAt(DateTime(2026, 5, 4, 10), entry.key)],
        );

        expect(series.axisStep, entry.value.$1,
            reason: '${entry.key} U should step by ${entry.value.$1}');
        expect(series.axisMax, entry.value.$2,
            reason: '${entry.key} U should top out at ${entry.value.$2}');
      }
    });

    /// The tallest bar reaches the top line rather than floating below an
    /// arbitrary one, and never overflows it.
    test('the tallest bar fits under the top line', () {
      for (final units in [0.3, 1.0, 2.7, 4.0, 9.9, 30.0]) {
        final series = seriesOf(
          meals: [bolusAt(DateTime(2026, 5, 4, 10), units)],
        );

        expect(series.axisMax, greaterThanOrEqualTo(units));
        expect(series.axisMax - series.axisStep, lessThan(units));
      }
    });
  });

  /// The bar the pointer picked has to compare equal to the bar being painted.
  ///
  /// [InsulinChartSeries.bars] hands out fresh objects, so under identity the
  /// painter matched nothing: it dimmed every bar to a third and highlighted
  /// none, which showed up as the whole chart fading out instead of one block
  /// being picked out.
  group('a picked bar is recognisable when it is painted', () {
    final hour = DateTime(2026, 5, 4, 9);
    final series = InsulinChartSeries(
      basalHours: [PodBasalHour(hour: hour, units: 0.8)],
      meals: const [],
      from: hour,
      to: hour.add(const Duration(hours: 2)),
    );

    test('the same bar read twice compares equal', () {
      expect(series.bars.first, series.bars.first);
    });

    test('a picked bar is found again among the painted ones', () {
      final picked = series.nearest(0.2);

      expect(series.bars.contains(picked), isTrue);
    });

    test('two different bars stay different', () {
      final other = InsulinChartSeries(
        basalHours: [PodBasalHour(hour: hour, units: 0.9)],
        meals: const [],
        from: hour,
        to: hour.add(const Duration(hours: 2)),
      );

      expect(series.bars.first == other.bars.first, isFalse);
    });
  });
}
