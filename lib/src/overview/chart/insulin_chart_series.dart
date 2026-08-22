import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/pump/pod_store.dart';

/// One drawable column of insulin.
class InsulinBar {
  const InsulinBar({
    required this.at,
    required this.coversUntil,
    required this.units,
    required this.isBolus,
  });

  /// When it went in. For basal this is the start of the hour it covers.
  final DateTime at;

  final double units;

  final bool isBolus;

  /// Where the delivery stops. A bolus is a moment and ends where it began; an
  /// hour of basal covers the hour, which is what lets it be drawn as the
  /// stretch it ran rather than as an event at the top of the hour.
  ///
  /// The hour in progress stops at the live edge rather than at the full hour,
  /// because the rest of it has not happened yet.
  final DateTime coversUntil;

  /// Compared by VALUE, which the highlighting depends on.
  ///
  /// [InsulinChartSeries.bars] used to build fresh objects on every read, so the
  /// bar the pointer picked was never the same instance as the one being
  /// painted. Under identity the painter therefore matched nothing: it dimmed
  /// every bar to a third and highlighted none, which showed up as the whole
  /// chart fading out instead of one block being picked out. The list is now
  /// computed once as well, but a chart must not depend on that to know which
  /// bar it is drawing.
  @override
  bool operator ==(Object other) =>
      other is InsulinBar &&
      other.at == at &&
      other.coversUntil == coversUntil &&
      other.units == units &&
      other.isBolus == isBolus;

  @override
  int get hashCode => Object.hash(at, coversUntil, units, isBolus);
}

/// Turns the insulin history into bars for a stretch of wall-clock time.
///
/// Separate from the widget that draws it so the arithmetic can be checked
/// without a screen, which matters more here than usual: this is the only place
/// in the app that puts basal and bolus on one axis, and getting the two mixed
/// up would misreport what somebody received.
///
/// The two kinds are deliberately NOT summed into one number. They are different
/// things: basal is a rate the pump ran for an hour, a bolus is a dose given at a
/// moment. Adding them would produce a total nobody can act on and would hide the
/// only distinction the chart exists to draw.
///
/// Boluses come from the MEAL log rather than the pod's delivery log, so a dose
/// injected by hand counts too. Basal comes from the pod's own hourly ledger,
/// which is the only record of it and already includes whatever the automation
/// delivered in the schedule's place.
class InsulinChartSeries {
  InsulinChartSeries({
    required this.basalHours,
    required this.meals,
    required this.from,
    required this.to,
    this.liveEdge,
  });

  final List<PodBasalHour> basalHours;
  final List<Meal> meals;
  final DateTime from;
  final DateTime to;

  /// Where measured data stops and the glucose chart's forecast begins.
  ///
  /// The window reaches past it to show that forecast, and this chart draws only
  /// things that have HAPPENED, so the hour in progress is cut here instead of
  /// running its full length across a stretch of time that has not occurred.
  /// Null leaves every hour at its full length, which is right when there is no
  /// sensor session to place a live edge with.
  final DateTime? liveEdge;

  /// Every bar visible in the window, oldest first.
  ///
  /// The two kinds are selected differently because they are different shapes. A
  /// bolus is a moment and is in or out. **An hour of basal is a stretch, so it
  /// counts whenever any part of it OVERLAPS the window**, not only when its
  /// start falls inside.
  ///
  /// Requiring the start was a real bug: a window opening at 09:30 dropped the
  /// 09:00 hour entirely, even though half of it was on screen, so a band the
  /// user could see the rest of simply vanished at the left edge. The painter
  /// clips what hangs over; that is the drawing's job, not the filter's.
  /// Computed once: the painter asks for the axis top once per bar it draws, and
  /// each of those walked this list again.
  late final List<InsulinBar> bars = _buildBars();

  List<InsulinBar> _buildBars() {
    final bars = <InsulinBar>[
      for (final hour in basalHours)
        if (hour.units > 0 && _overlapsWindow(hour.hour, _basalEnd(hour.hour)))
          InsulinBar(
            at: hour.hour,
            coversUntil: _basalEnd(hour.hour),
            units: hour.units,
            isBolus: false,
          ),
      for (final meal in meals)
        if (meal.bolus > 0 && _coversMoment(meal.time))
          InsulinBar(
            at: meal.time,
            coversUntil: meal.time,
            units: meal.bolus,
            isBolus: true,
          ),
    ]..sort((left, right) => left.at.compareTo(right.at));
    return bars;
  }

  /// Where an hour's band stops: the end of the hour, or the live edge when the
  /// hour is still running.
  DateTime _basalEnd(DateTime hour) {
    final end = hour.add(const Duration(hours: 1));
    final edge = liveEdge;
    if (edge == null || !edge.isBefore(end)) {
      return end;
    }
    return edge.isAfter(hour) ? edge : hour;
  }

  /// The tallest bar. Never zero, so an empty window still draws a sane scale
  /// rather than collapsing.
  late final double maxUnits = _maxUnits();

  double _maxUnits() {
    final tallest = bars.fold<double>(0, (top, bar) => bar.units > top ? bar.units : top);
    return tallest > 0 ? tallest : 1;
  }

  /// The gap between gridlines: the smallest round step that keeps the axis to
  /// four lines or fewer.
  ///
  /// Round numbers because the reader is meant to judge a bar against them at a
  /// glance. An axis topping out at the tallest bar plus a fixed percentage puts
  /// its lines at 2.4 and 4.8 units, which nobody can measure against.
  late final double axisStep = _axisStep();

  double _axisStep() {
    for (final step in const [0.5, 1.0, 2.0, 5.0, 10.0, 20.0]) {
      if (maxUnits / step <= 4) {
        return step;
      }
    }
    return 50;
  }

  /// The top of the axis: the tallest bar raised to the next whole step, so the
  /// tallest bar reaches the top line instead of floating below an arbitrary one.
  late final double axisMax = (maxUnits / axisStep).ceil() * axisStep;

  /// Basal in the window, counting an hour that only partly overlaps it by the
  /// share that does.
  ///
  /// Pro rata is exact rather than an approximation: within an hour the pump runs
  /// one rate, so half the hour is half the insulin. A bar hanging over the edge
  /// is still DRAWN at its full height, because that is the rate that hour ran;
  /// the legend answers a different question, which is how much went in over the
  /// stretch on screen.
  double get basalUnits {
    var units = 0.0;
    for (final bar in bars.where((entry) => !entry.isBolus)) {
      units += bar.units * _visibleShareOf(bar.at, bar.coversUntil);
    }
    return units;
  }

  double get bolusUnits => bars
      .where((bar) => bar.isBolus)
      .fold<double>(0, (sum, bar) => sum + bar.units);

  bool get isEmpty => bars.isEmpty;

  /// The meals inside the window, so their marker lines can be carried down from
  /// the glucose chart and run through this one as well.
  ///
  /// Two dashes stopping at a border read as two charts; one line crossing both
  /// is what makes a meal, the glucose after it and the insulin for it a single
  /// picture.
  List<Meal> get visibleMeals =>
      [for (final meal in meals) if (_coversMoment(meal.time)) meal];

  /// How much of [start] to [end] falls inside the window, from 0 to 1.
  double _visibleShareOf(DateTime start, DateTime end) {
    final span = end.difference(start).inSeconds;
    if (span <= 0) {
      return 0;
    }
    final visibleFrom = start.isBefore(from) ? from : start;
    final visibleTo = end.isAfter(to) ? to : end;
    final visible = visibleTo.difference(visibleFrom).inSeconds;
    return visible <= 0 ? 0 : (visible / span).clamp(0.0, 1.0);
  }

  /// Where [moment] falls across the window, 0 at its start and 1 at its end.
  ///
  /// This is what puts a bar under the glucose it belongs to. The glucose chart
  /// spans the same stretch across the same plot width, so the same fraction is
  /// the same pixel in both.
  double fractionOf(DateTime moment) {
    final span = to.difference(from).inSeconds;
    if (span <= 0) {
      return 0;
    }
    return (moment.difference(from).inSeconds / span).clamp(0.0, 1.0);
  }

  /// How close a bolus has to be to count as the thing being pointed at, as a
  /// share of the window. About the width of its own bar, so a fingertip lands
  /// on the spike it is aimed at.
  static const double bolusReach = 0.015;

  /// The bar the pointer is on at [fraction], or null when there are none.
  ///
  /// The two kinds are hit differently, because they are different shapes. A
  /// basal band covers an hour, so pointing anywhere inside that hour is
  /// pointing at it. A bolus is a spike, so it is hit within [bolusReach] of its
  /// own position.
  ///
  /// **A bolus wins where both are hit**, which is most of the time: a dose
  /// almost always lands inside an hour that was also running basal. The bolus
  /// is the discrete thing somebody is aiming at, and the basal it happened
  /// during can still be read off the band's width, while a bolus that cannot be
  /// selected cannot be read at all. Away from the spike, the same point falls
  /// back to the hour it is inside.
  InsulinBar? nearest(double fraction) {
    InsulinBar? closest;
    var best = double.infinity;
    for (final bar in bars) {
      final distance = _distanceTo(bar, fraction);
      final ties = (distance - best).abs() < 1e-9;
      if (distance < best || (ties && bar.isBolus)) {
        best = distance;
        closest = bar;
      }
    }
    return closest;
  }

  /// Zero while the pointer is on the bar, and the gap to it otherwise.
  double _distanceTo(InsulinBar bar, double fraction) {
    final start = fractionOf(bar.at);
    if (bar.isBolus) {
      final gap = (start - fraction).abs();
      return gap <= bolusReach ? 0 : gap;
    }
    final end = fractionOf(bar.coversUntil);
    if (fraction >= start && fraction <= end) {
      return 0;
    }
    return fraction < start ? start - fraction : fraction - end;
  }

  /// The window includes its start and excludes its end, so a moment on the
  /// boundary belongs to exactly one window.
  bool _coversMoment(DateTime moment) =>
      !moment.isBefore(from) && moment.isBefore(to);

  /// Whether any part of [start] to [end] is on screen. Touching the edge is not
  /// overlapping: an hour that ends exactly where the window begins has nothing
  /// inside it to draw.
  bool _overlapsWindow(DateTime start, DateTime end) =>
      start.isBefore(to) && end.isAfter(from);
}
