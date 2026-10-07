import 'dart:collection';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/base/hour_range_selector.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/cgm/glucose_prediction.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_detail_sheet.dart';
import 'package:insulink/src/overview/chart/chart_sync.dart';
import 'package:insulink/src/overview/chart/chart_window.dart';
import 'package:insulink/src/overview/chart/chart_x_axis.dart';
import 'package:insulink/src/overview/chart/glucose_chart_series.dart';
import 'package:insulink/src/overview/chart/glucose_line_chart.dart';
import 'package:insulink/src/overview/chart/insulin_bar_chart.dart';
import 'package:insulink/src/overview/chart/mirrored_readout.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/overview/chart/meal_label_strip.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/overview/chart/chart_range_switcher.dart';

/// fl_chart line graph of glucose vs. time (hours, 0 = latest reading).
class OverviewChart extends StatefulWidget {
  const OverviewChart({
    super.key,
    required this.byTime,
    this.sensorStart,
    this.preview = false,
    this.navigable = false,
    this.minYmgdl = 0,
    this.maxYmgdl = 300,
    this.showMeals = false,
    this.meals = const [],
    this.sync,
  });

  final SplayTreeMap<int, int> byTime;

  /// Overlay logged [meals] on the chart (dashed marker + tappable dot that opens
  /// the meal's details). Off by default; the detail page's toggle turns it on.
  final bool showMeals;
  final List<Meal> meals;

  /// Preview mode (on the overview): hide the range selector and disable touch,
  /// so an outer tap handler can open the full-screen detail page.
  final bool preview;

  /// Full-screen mode: show the interval navigator (prev/next) so the user can
  /// page back through earlier windows. Off on the preview.
  final bool navigable;

  /// Y-axis bounds in mg/dL — the overview passes adaptive values; the detail
  /// page keeps the full 0–300.
  final int minYmgdl;
  final int maxYmgdl;

  /// Wall-clock time the session started (`secsSinceStart == 0`). Lets the X
  /// axis show real clock times instead of hours-ago offsets.
  final DateTime? sensorStart;

  /// What this chart shares with the insulin chart stacked under it: the window,
  /// the axis labels, and the scrub.
  ///
  /// Non-null means the pair is drawn as one graph, which moves the axis labels
  /// down to the lower chart and makes a scrub on either show a readout on both.
  /// Null is a chart standing on its own (the overview preview).
  ///
  /// The window is never reported without a [sensorStart]: session seconds
  /// cannot be placed on a clock without one.
  final ChartSync? sync;

  @override
  State<OverviewChart> createState() => _OverviewChartState();
}

class _OverviewChartState extends State<OverviewChart> {
  static const _kRangeKey = 'chart_range_hours';
  static const _storage = FlutterSecureStorage();

  /// The last window handed to [OverviewChart.sync], so panning and zooming
  /// report once each and an ordinary rebuild reports nothing.
  (int, int, int)? _reportedWindow;

  /// The axis from the last build, so a touch can be turned into a fraction
  /// across the plot without redoing the window arithmetic.
  ChartXAxis? _axis;

  /// Visible time window in hours. The selector jumps to 6 / 12 / 24, but a
  /// two-finger pinch zooms it continuously between these bounds. The session
  /// history is capped at 24 h, so that is the widest useful window. Persisted.
  static const _minRangeHours = 0.5;
  static const _maxRangeHours = 24.0;
  double _rangeHours = _maxRangeHours;

  /// Seconds the view is scrolled BACK from the latest reading (0 = live). Kept
  /// in absolute time — NOT multiples of the window — so zooming leaves the
  /// scrolled-to position fixed instead of snapping back to now.
  int _panSecs = 0;

  /// Index of the transparent overlay bar that owns touch (so the haptic and
  /// tooltip ignore the per-zone colour bars + interpolated crossing points).
  int _touchBarIndex = 0;

  /// Spot index under the finger on the last touch event, so we only buzz once
  /// per data point as the finger moves across (and reset when it lifts off).
  int? _lastTouchedIndex;

  /// Active pointers by id and the finger distance on the previous move, so a
  /// pinch can be measured without stealing single-finger scrubbing from
  /// fl_chart (a plain [Listener] observes pointers in parallel, not a
  /// [GestureDetector], which would claim the touch).
  final Map<int, Offset> _pinchPointers = {};
  double? _pinchLastDistance;

  /// The two-finger focal point (global) on the previous move, so the gesture's
  /// horizontal travel can pan the time axis alongside the pinch zoom.
  Offset? _pinchLastFocal;

  /// Forecast horizon (hours past the latest reading) from the last build. The
  /// live right edge sits at this tip, so the navigator and its label read it to
  /// know where the window ends (one frame stale, which is harmless there).
  double _futureHours = 0;

  /// The chart's render box, so a pinch's focal point can be mapped to a
  /// fraction across the plot and the zoom can hold that spot in place.
  final GlobalKey _plotKey = GlobalKey();

  /// Width of the Y-axis label strip on the left (leftTitles reservedSize),
  /// excluded from the plotting area when mapping a focal point to time.
  static const _axisInset = InsulinBarChart.axisInset;

  /// Index of the (transparent) bar carrying the tappable meal dots, or -1 when
  /// the meal overlay is off, and the markers behind it — so a tap on a dot can
  /// resolve back to its [Meal] and open its details.
  int _mealBarIndex = -1;
  List<({double x, Meal meal})> _mealMarkers = const [];

  @override
  void initState() {
    super.initState();
    _loadRange();
    widget.sync
      ?..addListener(_onSyncChanged)
      ..onPinch = applyPinch;
  }

  @override
  void didUpdateWidget(OverviewChart old) {
    super.didUpdateWidget(old);
    if (old.sync == widget.sync) {
      return;
    }
    old.sync
      ?..removeListener(_onSyncChanged)
      ..onPinch = null;
    widget.sync
      ?..addListener(_onSyncChanged)
      ..onPinch = applyPinch;
  }

  /// Whether a readout driven from the chart below is on screen, so this chart
  /// redraws when that ENDS as well as when it starts.
  ///
  /// Rebuilding only while the mirror is wanted left the tooltip standing after
  /// the finger lifted: clearing the scrub turns the flag off, and a listener
  /// that reads the flag would then decide there was nothing to do.
  bool _showingMirror = false;

  /// Redraws for a scrub that came from the chart below. A window change is this
  /// chart's own doing and has already rebuilt it.
  void _onSyncChanged() {
    final sync = widget.sync!;
    final wanted = sync.scrubMirrored && sync.scrub != null;
    if (!mounted || (!wanted && !_showingMirror)) {
      return;
    }
    _showingMirror = wanted;
    setState(() {});
  }

  /// The tick a finger gets as it crosses a reading, given for a scrub on the
  /// chart below as well as for one here.
  ///
  /// Per READING, not per pixel: it is the same feedback either way round, and a
  /// buzz on every pointer move would be a rattle rather than a signal.
  void _buzzForMirror(int? mirrored) {
    if (_lastMirroredIndex == mirrored) {
      return;
    }
    _lastMirroredIndex = mirrored;
    if (mirrored != null) {
      HapticFeedback.selectionClick();
    }
  }

  int? _lastMirroredIndex;

  @override
  void dispose() {
    widget.sync
      ?..removeListener(_onSyncChanged)
      ..onPinch = null;
    super.dispose();
  }

  Future<void> _loadRange() async {
    final stored = double.tryParse(await _storage.read(key: _kRangeKey) ?? '');
    if (mounted &&
        stored != null &&
        stored >= _minRangeHours &&
        stored <= _maxRangeHours) {
      setState(() => _rangeHours = stored);
    }
  }

  /// A range picked on the selector, as opposed to a pinch: the one change the
  /// chart cross-fades for ([ChartRangeSwitcher]).
  int _rangeSwitches = 0;

  void _setRange(int hours) {
    _rangeSwitches++;
    widget.sync?.noteRangeSwitch();
    _applyRange(hours.toDouble());
    _persistRange();
  }

  void _applyRange(double hours) {
    final clamped = hours.clamp(_minRangeHours, _maxRangeHours);
    setState(() {
      _rangeHours = clamped;
    });
  }

  void _persistRange() {
    _storage.write(key: _kRangeKey, value: '$_rangeHours');
  }

  void _onPinchPointerDown(PointerDownEvent event) {
    _pinchPointers[event.pointer] = event.position;
    if (_pinchPointers.length == 2) {
      _pinchLastDistance = _pinchDistance();
      _pinchLastFocal = _pinchFocalGlobal();
    }
  }

  /// Handles both parts of a two-finger gesture each move: the fingers spreading
  /// or pinching zooms the window (anchored under the focal point), and the
  /// focal point sliding sideways pans the time axis. Both compose, like a map.
  void _onPinchPointerMove(PointerMoveEvent event) {
    if (!_pinchPointers.containsKey(event.pointer)) {
      return;
    }
    _pinchPointers[event.pointer] = event.position;
    if (_pinchPointers.length != 2 || _pinchLastDistance == null) {
      return;
    }
    final distance = _pinchDistance();
    if (distance <= 0) {
      return;
    }
    final box = _plotKey.currentContext?.findRenderObject() as RenderBox?;
    final focal = _pinchFocalGlobal();
    // Both previous values are read BEFORE they are replaced. Overwriting the
    // distance first makes every scale exactly 1.0, which is a pinch that
    // silently does nothing.
    final previousDistance = _pinchLastDistance!;
    final travel = _pinchLastFocal == null
        ? 0.0
        : focal.dx - _pinchLastFocal!.dx;
    _pinchLastDistance = distance;
    _pinchLastFocal = focal;
    applyPinch(
      scale: distance / previousDistance,
      focalTravelX: travel,
      plotWidth: (box?.size.width ?? 0) - _axisInset,
      focalFraction: _focalFraction(box),
    );
  }

  /// Applies a two-finger gesture, wherever over the pair it was measured.
  ///
  /// Public and registered on the shared [ChartSync] because the range and the
  /// scroll position live here: a pinch over the insulin chart underneath has to
  /// move THIS window, or the two would drift apart and stop being one graph.
  void applyPinch({
    required double scale,
    required double focalTravelX,
    required double plotWidth,
    required double focalFraction,
  }) {
    if (scale <= 0) {
      return;
    }
    final oldRange = _rangeHours;
    final newRange = (oldRange / scale).clamp(_minRangeHours, _maxRangeHours);
    // Zoom: hold the time under the fingers in place — the window to the RIGHT
    // of the focal point is what a range change adds to / removes from the
    // scroll-back offset.
    var deltaSecs = (oldRange - newRange) * 3600 * (1.0 - focalFraction);
    // Pan: convert the focal point's sideways travel to time (fingers moving
    // right pulls older data into view, i.e. scrolls back).
    if (plotWidth > 0) {
      deltaSecs += focalTravelX * newRange * 3600 / plotWidth;
    }
    setState(() {
      _rangeHours = newRange;
      _panSecs = (_panSecs + deltaSecs.round()).clamp(0, 1 << 30);
    });
  }

  Offset _pinchFocalGlobal() {
    final points = _pinchPointers.values.toList();
    return (points[0] + points[1]) / 2;
  }

  /// Where the pinch sits across the plot: 0 = left edge, 1 = right edge.
  /// Falls back to the right edge (the old always-anchor-now behaviour) when the
  /// geometry isn't available.
  double _focalFraction(RenderBox? box) {
    if (box == null || _pinchPointers.length < 2) {
      return 1.0;
    }
    final focalX = box.globalToLocal(_pinchFocalGlobal()).dx;
    final plotWidth = box.size.width - _axisInset;
    if (plotWidth <= 0) {
      return 1.0;
    }
    return ((focalX - _axisInset) / plotWidth).clamp(0.0, 1.0);
  }

  void _onPinchPointerUp(PointerEvent event) {
    final wasPinching = _pinchPointers.length == 2;
    _pinchPointers.remove(event.pointer);
    if (_pinchPointers.length < 2) {
      _pinchLastDistance = null;
      _pinchLastFocal = null;
      if (wasPinching) {
        _persistRange();
      }
    }
  }

  double _pinchDistance() {
    final points = _pinchPointers.values.toList();
    return (points[0] - points[1]).distance;
  }

  /// Light haptic tick when the highlighted point changes while scrubbing. Use
  /// the overlay (real-reading) bar's spot, so movement is tracked per actual
  /// reading rather than per colour segment.
  /// Drops the scrub readout. A tap on a meal ends the touch too: it opens
  /// the meal's sheet, and a readout left standing would keep the chart in
  /// hover mode behind it and after it closes.
  void _endScrub() {
    _lastTouchedIndex = null;
    widget.sync?.setScrub(null);
  }

  void _onChartTouch(FlTouchEvent event, LineTouchResponse? response) {
    final spots = response?.lineBarSpots;
    if (event is FlTapUpEvent && spots != null && _mealBarIndex >= 0) {
      for (final spot in spots) {
        if (spot.barIndex == _mealBarIndex &&
            spot.spotIndex < _mealMarkers.length) {
          _endScrub();
          showMealDetail(context, _mealMarkers[spot.spotIndex].meal);
          return;
        }
      }
    }
    if (!event.isInterestedForInteractions || spots == null || spots.isEmpty) {
      _endScrub();
      return;
    }
    final touch = spots.firstWhere(
      (spot) => spot.barIndex == _touchBarIndex,
      orElse: () => spots.first,
    );
    widget.sync?.setScrub(_axis?.fractionOf(touch.x));
    if (touch.spotIndex != _lastTouchedIndex) {
      _lastTouchedIndex = touch.spotIndex;
      HapticFeedback.selectionClick();
    }
  }

  /// The spot to draw a readout on because the chart BELOW is being scrubbed, so
  /// one finger produces one reading across the pair. Null while this chart owns
  /// the gesture, which leaves fl_chart's own touch handling to draw it.
  int? _mirroredSpot(List<FlSpot> touchSpots) {
    final sync = widget.sync;
    final axis = _axis;
    if (sync == null || axis == null || !sync.scrubMirrored) {
      return null;
    }
    final fraction = sync.scrub;
    if (fraction == null || touchSpots.isEmpty) {
      return null;
    }
    final wanted = axis.minX + fraction * (axis.maxX - axis.minX);
    var nearest = 0;
    for (var index = 1; index < touchSpots.length; index++) {
      if ((touchSpots[index].x - wanted).abs() <
          (touchSpots[nearest].x - wanted).abs()) {
        nearest = index;
      }
    }
    return nearest;
  }

  /// Hands the pair the stretch of wall-clock time on screen and the labels for
  /// it.
  ///
  /// After the frame, not during it: the chart below rebuilds on this, and doing
  /// that from inside this build would rebuild this widget from its own build.
  void _reportWindow(
    BuildContext context,
    ChartXAxis axis,
    int fromSecs,
    int toSecs,
    int liveSecs,
  ) {
    final sync = widget.sync;
    final start = widget.sensorStart;
    if (sync == null ||
        start == null ||
        _reportedWindow == (fromSecs, toSecs, liveSecs)) {
      return;
    }
    _reportedWindow = (fromSecs, toSecs, liveSecs);
    final ticks = axis.ticks(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        sync.reportWindow(
          from: start.add(Duration(seconds: fromSecs)),
          to: start.add(Duration(seconds: toSecs)),
          liveEdge: start.add(Duration(seconds: liveSecs)),
          ticks: ticks,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final glucose = context.watch<ProfileGlucoseState>();
    final colors = Theme.of(context).extension<GlucoseColors>()!;
    final byTime = widget.byTime;
    if (byTime.isEmpty) {
      return Center(child: LocaleText('overview.chart.empty'));
    }
    if (widget.preview) {
      return _chart(byTime, glucose, colors);
    }
    // Built first: it settles the window and the meal markers the labels read.
    final chart = _chart(byTime, glucose, colors);
    final labels = _mealStrip();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            HourRangeSelector(
              selected: _rangeHours.round(),
              onChanged: _setRange,
            ),
            if (widget.navigable) Flexible(child: _navigator(context, byTime)),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _pinchable(
            ChartRangeSwitcher(
              generation: _rangeSwitches,
              child: _withMealLabels(chart, labels),
            ),
          ),
        ),
      ],
    );
  }

  /// The carb labels laid INTO the chart at its top, so they cost the plot no
  /// height. Touches go through them to the chart.
  ///
  /// They step aside while a value is read out, from either chart of the pair:
  /// the readout sits above the reading, which near the top of the plot is
  /// exactly where the labels are, and a readout half hidden behind a pill is
  /// no readout. Only the labels listen, so a scrub still rebuilds nothing else.
  Widget _withMealLabels(Widget chart, Widget? labels) {
    if (labels == null) {
      return chart;
    }
    final sync = widget.sync;
    return Stack(
      children: [
        Positioned.fill(child: chart),
        Positioned(
          top: 4,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: sync == null
                ? labels
                : ListenableBuilder(
                    listenable: sync,
                    builder: (_, child) => AnimatedOpacity(
                      opacity: sync.scrub == null ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: child,
                    ),
                    child: labels,
                  ),
          ),
        ),
      ],
    );
  }

  /// The carb labels, one pill per visible meal; the strip measures them and
  /// stacks the ones that would touch. Null without meals.
  Widget? _mealStrip() {
    final axis = _axis;
    if (axis == null || _mealMarkers.isEmpty) {
      return null;
    }
    return MealLabelStrip(
      stripWidth: _axisInset,
      labels: [
        for (final marker in _mealMarkers)
          (
            fraction: axis.fractionOf(marker.x),
            text: '${sportDecimal(marker.meal.carbs, 0)} g',
          ),
      ],
    );
  }

  /// Watches for a two-finger gesture, unless something above is already doing
  /// it for the whole pair.
  ///
  /// Both at once would apply every pinch TWICE, at the square of the intended
  /// zoom. When the chart is stacked with another, the gesture belongs to the
  /// pair rather than to either half, so the outer one wins and this only keeps
  /// its key, which the focal-point arithmetic needs.
  Widget _pinchable(Widget chart) {
    if (widget.sync != null) {
      return KeyedSubtree(key: _plotKey, child: chart);
    }
    return Listener(
      key: _plotKey,
      onPointerDown: _onPinchPointerDown,
      onPointerMove: _onPinchPointerMove,
      onPointerUp: _onPinchPointerUp,
      onPointerCancel: _onPinchPointerUp,
      child: chart,
    );
  }

  /// Prev/next interval navigator: pages the visible window back through earlier
  /// days and forward again to the live window (0). Disabled at each end.
  Widget _navigator(BuildContext context, SplayTreeMap<int, int> byTime) {
    final latestSecs = byTime.isEmpty ? 0 : byTime.lastKey()!;
    final oldestSecs = byTime.isEmpty ? 0 : byTime.firstKey()!;
    // Right edge sits at the forecast tip when live (_panSecs == 0); the horizon
    // is from the last build (one frame stale, fine for enabling the button).
    final horizonSecs = (_futureHours * 3600).round();
    final windowStartSecs =
        _liveEdgeSecs(latestSecs) +
        horizonSecs -
        _panSecs -
        (_rangeHours * 3600).round();
    final canGoBack = windowStartSecs > oldestSecs;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(PhosphorIconsBold.caretLeft, size: 22),
          onPressed: canGoBack ? () => _pan(1) : null,
        ),
        Flexible(
          child: Text(
            _navigatorLabel(context),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(PhosphorIconsBold.caretRight, size: 22),
          onPressed: _panSecs > 0 ? () => _pan(-1) : null,
        ),
      ],
    );
  }

  /// The window's live right edge in session-seconds — now, not the newest
  /// reading. See [liveWindowEdgeSecs] for why the difference matters.
  int _liveEdgeSecs(int latestSecs) => liveWindowEdgeSecs(
    latestSecs: latestSecs,
    sensorStart: widget.sensorStart,
    now: DateTime.now(),
  );

  /// Pages by one current window: [direction] > 0 goes back, < 0 forward.
  void _pan(int direction) {
    final step = (_rangeHours * 3600).round();
    setState(() {
      _panSecs = (_panSecs + direction * step).clamp(0, 1 << 30);
    });
  }

  /// "Jetzt" while the right edge still reaches the latest reading (through the
  /// forecast), else the wall-clock time at the right edge of the earlier window.
  String _navigatorLabel(BuildContext context) {
    final start = widget.sensorStart;
    final horizonSecs = (_futureHours * 3600).round();
    if (_panSecs <= horizonSecs || start == null || widget.byTime.isEmpty) {
      return Locales.string(context, 'overview.chart.now');
    }
    final latestSecs = widget.byTime.lastKey()!;
    final end = start.add(
      Duration(seconds: _liveEdgeSecs(latestSecs) + horizonSecs - _panSecs),
    );
    final l10n = MaterialLocalizations.of(context);
    final time = l10n.formatTimeOfDay(TimeOfDay.fromDateTime(end));
    return '${l10n.formatMediumDate(end)}, $time';
  }

  Widget _chart(
    SplayTreeMap<int, int> byTime,
    ProfileGlucoseState glucose,
    GlucoseColors colors,
  ) {
    final entries = byTime.entries.toList();
    final latestSecs = entries.last.key;
    final controller = context.watch<CgmController>();
    // The overview preview always shows 24 h; only the full-screen detail page
    // honours the persisted, user-selectable range.
    final effectiveRange = widget.preview ? 24.0 : _rangeHours;
    // At rest the window's right edge sits just past the latest reading to show
    // the forecast; the window is always `range` wide and scrolling back slides
    // the right edge left through the readings, so the width never changes and
    // the forecast just glides off instead of popping the window narrower. Cap
    // the live forecast to ~40 % of the window so a deep zoom still shows real
    // readings rather than only the forecast.
    final horizonHours = _horizonHours(controller, latestSecs);
    final liveForecastHours = math.min(horizonHours, effectiveRange * 0.4);
    _futureHours = widget.preview ? 0 : liveForecastHours;
    final panSecs = widget.preview ? 0 : _panSecs;
    final windowEndSecs =
        _liveEdgeSecs(latestSecs) +
        (liveForecastHours * 3600).round() -
        panSecs;
    final rightEdgeHours = (windowEndSecs - latestSecs) / 3600.0;
    // Wall-clock time at x == 0 (the latest reading), to label the X axis with
    // real times. x is hours relative to this, so wall(x) = anchor + x hours.
    final anchor = widget.sensorStart?.add(Duration(seconds: latestSecs));
    // Phase-shift X so full wall-clock hours land on integer x values (the axis
    // ticks): shift = the fractional-hour part of the latest reading's time.
    final shift = anchor == null
        ? 0.0
        : (anchor.minute * 60 + anchor.second) / 3600.0;
    final cutoffSecs = (windowEndSecs - effectiveRange * 3600).round();
    final axis = ChartXAxis(
      shift: shift,
      rangeHours: effectiveRange,
      rightEdgeHours: rightEdgeHours,
      anchor: anchor,
    );
    _axis = axis;
    _reportWindow(context, axis, cutoffSecs, windowEndSecs, latestSecs);
    final series = GlucoseChartSeries(
      entries: entries,
      latestSecs: latestSecs,
      cutoff: cutoffSecs,
      windowEnd: windowEndSecs,
      shift: shift,
      glucose: glucose,
      colors: colors,
      minimal: widget.preview,
    );
    final bars = series.buildBars();
    // Dashed forecast line past the latest reading. Always built (anchored at the
    // latest reading, not the scroll position) and clipped by fl_chart once
    // scrolled out — the window width is constant, so nothing jumps.
    final showBand = context.watch<ProfilePredictionState>().band;
    final prediction = _addPredictionBar(
      bars,
      controller,
      entries,
      latestSecs,
      shift,
      glucose,
      showBand,
    );
    // Transparent overlay owning touch — over the REAL readings AND the forecast
    // points, so scrubbing snaps to a single value in either region (not to the
    // zone bars, which share boundary points, or the interpolated crossings).
    _touchBarIndex = bars.length;
    final touchSpots = [...series.realSpots, ...prediction.touchSpots];
    bars.add(_touchBar(touchSpots));
    // Which spot a scrub on the chart below is pointing at, drawn as an overlay
    // rather than handed to fl_chart. See [MirroredReadout] for why.
    final mirrored = _mirroredSpot(touchSpots);
    // Meal overlay: a marker line per logged meal (drawn by GlucoseLineChart)
    // plus a transparent bar of tappable dots appended here, so a tap resolves
    // to a meal via its spot index.
    final mealMarkers = _buildMealMarkers(
      anchor,
      shift,
      effectiveRange,
      rightEdgeHours,
    );
    _mealMarkers = mealMarkers;
    if (mealMarkers.isEmpty) {
      _mealBarIndex = -1;
    } else {
      _mealBarIndex = bars.length;
      bars.add(_mealBar(mealMarkers, glucose));
    }
    final highlightSpot = series.realSpots.isEmpty
        ? null
        : series.realSpots.last;
    // Remount on each data change so fl_chart renders the new data statically
    // instead of tweening between structurally-different bar lists — that lerp
    // flashes a malformed frame even with a zero-duration animation.
    final predictionCount = controller.predictionCurve?.length ?? 0;
    // The band adds two bars, so toggling it changes the bar structure — it has
    // to take part in the key or fl_chart tweens between mismatched lists.
    final key = ValueKey(
      '$latestSecs-${entries.length}-$effectiveRange-$panSecs'
      '-$predictionCount-${prediction.band != null}-${mealMarkers.length}',
    );
    final chart = GlucoseLineChart(
      key: key,
      bars: bars,
      betweenBars: [if (prediction.band != null) prediction.band!],
      touchBarIndex: _touchBarIndex,
      axis: axis,
      glucose: glucose,
      colors: colors,
      onChartTouch: _onChartTouch,
      interactive: !widget.preview,
      minimal: widget.preview,
      minYmgdl: widget.minYmgdl,
      maxYmgdl: widget.maxYmgdl,
      highlightSpot: widget.preview ? highlightSpot : null,
      // The labels move under the insulin chart whenever one is stacked below,
      // so the two plots touch and read as one picture with one axis.
      showBottomTitles: widget.sync == null,
      mealMarkers: mealMarkers,
    );
    if (widget.preview) {
      return chart;
    }
    _buzzForMirror(mirrored);
    return _withMirror(chart, touchSpots, mirrored, axis, glucose);
  }

  /// Lays the readout for a scrub on the chart below over this one.
  ///
  /// An overlay because fl_chart discards a tooltip set from outside: see
  /// [MirroredReadout]. Nothing is added while this chart owns the gesture, where
  /// its own touch handling draws it.
  Widget _withMirror(
    Widget chart,
    List<FlSpot> touchSpots,
    int? mirrored,
    ChartXAxis axis,
    ProfileGlucoseState glucose,
  ) {
    final fraction = widget.sync?.scrub;
    if (mirrored == null || fraction == null || mirrored >= touchSpots.length) {
      return chart;
    }
    final spot = touchSpots[mirrored];
    final digits = glucose.unit == GlucoseUnit.mmol ? 1 : 0;
    // Past the latest reading is the forecast, marked as an estimate exactly as
    // this chart's own tooltip marks it.
    final forecast = spot.x > axis.shift;
    final top = glucose.toDisplay(widget.maxYmgdl);
    final bottom = glucose.toDisplay(widget.minYmgdl);
    return Stack(
      children: [
        Positioned.fill(child: chart),
        Positioned.fill(
          child: IgnorePointer(
            child: MirroredReadout(
              fraction: fraction,
              valueFraction: top == bottom
                  ? 0.5
                  : ((top - spot.y) / (top - bottom)).clamp(0.0, 1.0),
              dotColor: forecast ? _predictionGrey() : _zoneColorFor(spot.y),
              value:
                  '${forecast ? '~' : ''}'
                  '${spot.y.toStringAsFixed(digits)} ${glucose.unit.label}',
              time: _clockAt(axis, spot.x),
              axisInset: _axisInset,
            ),
          ),
        ),
      ],
    );
  }

  /// The zone colour of a display-unit value, the same rule this chart's own
  /// touch dot follows.
  Color _zoneColorFor(double displayed) {
    final glucose = context.read<ProfileGlucoseState>();
    final colors = Theme.of(context).extension<GlucoseColors>()!;
    if (displayed < glucose.toDisplay(glucose.targetLow)) {
      return colors.low;
    }
    if (displayed > glucose.toDisplay(glucose.targetHigh)) {
      return colors.high;
    }
    return colors.inRange;
  }

  /// A forecast point is not a measured value, so it never wears a glucose zone.
  Color _predictionGrey() => HSLColor.fromColor(
    Theme.of(context).colorScheme.onSurface,
  ).withLightness(0.6).toColor();

  /// The wall-clock time at an x, the same mapping the axis labels use.
  String _clockAt(ChartXAxis axis, double x) {
    final anchor = axis.anchor;
    if (anchor == null) {
      return '';
    }
    final time = anchor.add(
      Duration(seconds: ((x - axis.shift) * 3600).round()),
    );
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(time));
  }

  /// Forecast horizon in hours past the latest reading (0 when there is no live
  /// forecast). Mirrors [_addPredictionBar] so the window's right edge reserves
  /// exactly the span the dashed line occupies.
  double _horizonHours(CgmController controller, int latestSecs) {
    final curve = controller.predictionCurve;
    final base = controller.predictionBase;
    final start = widget.sensorStart;
    if (curve == null || base == null || start == null || curve.isEmpty) {
      return 0;
    }
    final baseSecs = base.difference(start).inSeconds;
    final lastSecs = baseSecs + curve.last.offsetMin * 60;
    return ((lastSecs - latestSecs) / 3600.0).clamp(0.0, 24.0);
  }

  /// Appends the dashed forecast bar (anchored at the latest reading), and the
  /// two invisible band edges under it when the band overlay is on. Returns how
  /// many hours the forecast extends past the latest reading (so the X axis can
  /// widen to fit), the future points — which the touch overlay also covers so
  /// they're hoverable — and the band fill, if any. No forecast / no session
  /// clock → nothing added, 0 / empty.
  ///
  /// The band edges go in BEFORE the mean line so the fill paints under it.
  ({double futureHours, List<FlSpot> touchSpots, BetweenBarsData? band})
  _addPredictionBar(
    List<LineChartBarData> bars,
    CgmController controller,
    List<MapEntry<int, int>> entries,
    int latestSecs,
    double shift,
    ProfileGlucoseState glucose,
    bool showBand,
  ) {
    final curve = controller.predictionCurve;
    final base = controller.predictionBase;
    final start = widget.sensorStart;
    if (curve == null || base == null || start == null || entries.isEmpty) {
      return (futureHours: 0, touchSpots: const <FlSpot>[], band: null);
    }
    final baseSecs = base.difference(start).inSeconds;
    final anchor = FlSpot(shift, glucose.toDisplay(entries.last.value));
    final spots = _predictionSpots(curve, baseSecs, latestSecs, shift, glucose);
    if (spots.mean.isEmpty) {
      return (futureHours: 0, touchSpots: const <FlSpot>[], band: null);
    }
    final band = showBand ? _addBandBars(bars, spots, anchor) : null;
    bars.add(_predictionBar([anchor, ...spots.mean]));
    final lastSecs = baseSecs + curve.last.offsetMin * 60;
    return (
      futureHours: ((lastSecs - latestSecs) / 3600.0).clamp(0.0, 24.0),
      touchSpots: spots.mean,
      band: band,
    );
  }

  /// The forecast curve as chart spots: the mean line plus its q10/q90 edges.
  ///
  /// Only points still ahead of the latest reading. A stale forecast (base older
  /// than the newest reading because a refresh failed) otherwise draws its early
  /// points to the LEFT of x=0, overlapping the real readings. A point whose
  /// model served no band collapses its edges onto the mean, so a pre-band model
  /// simply draws no band rather than a broken one.
  ({List<FlSpot> mean, List<FlSpot> low, List<FlSpot> high, bool hasBand})
  _predictionSpots(
    List<PredictionPoint> curve,
    int baseSecs,
    int latestSecs,
    double shift,
    ProfileGlucoseState glucose,
  ) {
    final mean = <FlSpot>[];
    final low = <FlSpot>[];
    final high = <FlSpot>[];
    var hasBand = false;
    for (final point in curve) {
      final secs = baseSecs + point.offsetMin * 60;
      if (secs <= latestSecs) {
        continue;
      }
      final x = (secs - latestSecs) / 3600.0 + shift;
      mean.add(FlSpot(x, glucose.toDisplay(point.mgdl)));
      low.add(FlSpot(x, glucose.toDisplay(point.lo ?? point.mgdl)));
      high.add(FlSpot(x, glucose.toDisplay(point.hi ?? point.mgdl)));
      hasBand = hasBand || point.lo != null || point.hi != null;
    }
    return (mean: mean, low: low, high: high, hasBand: hasBand);
  }

  /// Append the two invisible band-edge bars and return the fill between them,
  /// or null when the curve carries no bounds at all (a pre-band model). Both
  /// edges start at [anchor] so the band opens from the current reading instead
  /// of appearing out of nowhere at the first forecast point.
  BetweenBarsData? _addBandBars(
    List<LineChartBarData> bars,
    ({List<FlSpot> mean, List<FlSpot> low, List<FlSpot> high, bool hasBand})
    spots,
    FlSpot anchor,
  ) {
    if (!spots.hasBand) {
      return null;
    }
    bars.add(_bandEdgeBar([anchor, ...spots.low]));
    bars.add(_bandEdgeBar([anchor, ...spots.high]));
    return BetweenBarsData(
      fromIndex: bars.length - 2,
      toIndex: bars.length - 1,
      color: context.ink.text.withValues(alpha: 0.08),
    );
  }

  /// An invisible band edge: it exists only to bound the fill, so it carries no
  /// visible stroke. Curve settings mirror [_predictionBar] — a differently
  /// smoothed edge would drift away from the mean line it wraps. Its barWidth is
  /// deliberately NON-zero (transparent): a zero-width bar reads as the touch
  /// overlay to `_indicators`, so hovering near the forecast boundary would draw
  /// a stray scrub dot on the edge's anchor. Same trick as `_mealBar`.
  LineChartBarData _bandEdgeBar(List<FlSpot> spots) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.4,
      barWidth: 2,
      color: Colors.transparent,
      dotData: const FlDotData(show: false),
    );
  }

  /// The forecast line: a smooth curve with a dot on the final point so the
  /// short stub stays legible. Overshoot-prevention is deliberately OFF here —
  /// it clamps the spline flat at turning points (which is what stopped the
  /// curve looking smooth); the gently-varying forecast values don't overshoot
  /// enough to matter.
  LineChartBarData _predictionBar(List<FlSpot> spots) {
    final lineColor = context.ink.muted;
    final dotColor = context.ink.muted;
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.4,
      barWidth: 2.5,
      dashArray: const [6, 5],
      color: lineColor,
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, bar) => spot.x == bar.spots.last.x,
        getDotPainter: (spot, _, _, _) =>
            FlDotCirclePainter(radius: 3.5, color: dotColor, strokeWidth: 0),
      ),
    );
  }

  /// Logged meals as (x, meal) markers, kept to the visible window so a long
  /// history draws only a handful of lines. x maps a meal's wall-clock time the
  /// same way readings map: `(time - anchor)` hours, phase-shifted. Empty when
  /// the overlay is off or the session clock is unknown (no [anchor]).
  List<({double x, Meal meal})> _buildMealMarkers(
    DateTime? anchor,
    double shift,
    double effectiveRange,
    double rightEdgeHours,
  ) {
    if (!widget.showMeals || anchor == null || widget.meals.isEmpty) {
      return const [];
    }
    final minX = shift + rightEdgeHours - effectiveRange - 0.5;
    final maxX = shift + rightEdgeHours + 0.5;
    final markers = <({double x, Meal meal})>[];
    for (final meal in widget.meals) {
      final x = meal.time.difference(anchor).inSeconds / 3600.0 + shift;
      if (x >= minX && x <= maxX) {
        markers.add((x: x, meal: meal));
      }
    }
    return markers;
  }

  /// Transparent bar carrying one visible dot per meal at the glucose it was
  /// logged with. Its non-zero barWidth (with a transparent colour) keeps the
  /// scrub indicator off it while leaving the dots hoverable for taps.
  LineChartBarData _mealBar(
    List<({double x, Meal meal})> markers,
    ProfileGlucoseState glucose,
  ) {
    final ink = context.ink;
    return LineChartBarData(
      spots: [
        for (final marker in markers)
          FlSpot(marker.x, glucose.toDisplay(marker.meal.glucoseMgdl)),
      ],
      barWidth: 2,
      color: Colors.transparent,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
          radius: 5,
          color: ink.text,
          strokeColor: ink.ground,
          strokeWidth: 2.5,
        ),
      ),
    );
  }

  LineChartBarData _touchBar(List<FlSpot> realSpots) {
    return LineChartBarData(
      spots: realSpots,
      isCurved: true,
      curveSmoothness: 0.2,
      preventCurveOverShooting: true,
      barWidth: 0,
      color: Colors.transparent,
      dotData: const FlDotData(show: false),
    );
  }
}
