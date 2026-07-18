import 'dart:collection';

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
import 'package:insulink/src/overview/chart/glucose_chart_series.dart';
import 'package:insulink/src/overview/chart/glucose_line_chart.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

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

  @override
  State<OverviewChart> createState() => _OverviewChartState();
}

class _OverviewChartState extends State<OverviewChart>
    with SingleTickerProviderStateMixin {
  static const _kRangeKey = 'chart_range_hours';
  static const _storage = FlutterSecureStorage();

  /// Visible time window in hours (selectable: 6 / 12 / 24). Persisted.
  int _rangeHours = 24;

  /// How many whole windows the view is scrolled BACK from the latest reading
  /// (0 = live). Reset whenever the range changes.
  int _panWindows = 0;

  /// Drives the latest-reading dot's pulsing halo.
  late final AnimationController _pulse;

  /// Index of the transparent overlay bar that owns touch (so the haptic and
  /// tooltip ignore the per-zone colour bars + interpolated crossing points).
  int _touchBarIndex = 0;

  /// Spot index under the finger on the last touch event, so we only buzz once
  /// per data point as the finger moves across (and reset when it lifts off).
  int? _lastTouchedIndex;

  /// Index of the (transparent) bar carrying the tappable meal dots, or -1 when
  /// the meal overlay is off, and the markers behind it — so a tap on a dot can
  /// resolve back to its [Meal] and open its details.
  int _mealBarIndex = -1;
  List<({double x, Meal meal})> _mealMarkers = const [];

  @override
  void initState() {
    super.initState();
    _loadRange();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _loadRange() async {
    final stored = int.tryParse(await _storage.read(key: _kRangeKey) ?? '');
    if (mounted && (stored == 6 || stored == 12 || stored == 24)) {
      setState(() => _rangeHours = stored!);
    }
  }

  void _setRange(int hours) {
    setState(() {
      _rangeHours = hours;
      _panWindows = 0;
    });
    _storage.write(key: _kRangeKey, value: '$hours');
  }

  /// Light haptic tick when the highlighted point changes while scrubbing. Use
  /// the overlay (real-reading) bar's spot, so movement is tracked per actual
  /// reading rather than per colour segment.
  void _onChartTouch(FlTouchEvent event, LineTouchResponse? response) {
    final spots = response?.lineBarSpots;
    if (event is FlTapUpEvent && spots != null && _mealBarIndex >= 0) {
      for (final spot in spots) {
        if (spot.barIndex == _mealBarIndex &&
            spot.spotIndex < _mealMarkers.length) {
          showMealDetail(context, _mealMarkers[spot.spotIndex].meal);
          return;
        }
      }
    }
    if (!event.isInterestedForInteractions || spots == null || spots.isEmpty) {
      _lastTouchedIndex = null;
      return;
    }
    final touch = spots.firstWhere(
      (spot) => spot.barIndex == _touchBarIndex,
      orElse: () => spots.first,
    );
    if (touch.spotIndex != _lastTouchedIndex) {
      _lastTouchedIndex = touch.spotIndex;
      HapticFeedback.selectionClick();
    }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            HourRangeSelector(selected: _rangeHours, onChanged: _setRange),
            if (widget.navigable) Flexible(child: _navigator(context, byTime)),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(child: _chart(byTime, glucose, colors)),
      ],
    );
  }

  /// Prev/next interval navigator: pages the visible window back through earlier
  /// days and forward again to the live window (0). Disabled at each end.
  Widget _navigator(BuildContext context, SplayTreeMap<int, int> byTime) {
    final latestSecs = byTime.isEmpty ? 0 : byTime.lastKey()!;
    final oldestSecs = byTime.isEmpty ? 0 : byTime.firstKey()!;
    final windowStartSecs = latestSecs - (_panWindows + 1) * _rangeHours * 3600;
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
          onPressed: _panWindows > 0 ? () => _pan(-1) : null,
        ),
      ],
    );
  }

  void _pan(int windows) {
    setState(() => _panWindows = (_panWindows + windows).clamp(0, 1000));
  }

  /// "Jetzt" for the live window, else the wall-clock date at the window's end.
  String _navigatorLabel(BuildContext context) {
    final start = widget.sensorStart;
    if (_panWindows == 0 || start == null || widget.byTime.isEmpty) {
      return Locales.string(context, 'overview.chart.now');
    }
    final latestSecs = widget.byTime.lastKey()!;
    final end = start.add(
      Duration(seconds: latestSecs - _panWindows * _rangeHours * 3600),
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
    // The overview preview always shows 24 h; only the full-screen detail page
    // honours the persisted, user-selectable range.
    final effectiveRange = widget.preview ? 24 : _rangeHours;
    // Windows scrolled back from the latest reading (the preview never pans).
    final panWindows = widget.preview ? 0 : _panWindows;
    final panSecs = panWindows * effectiveRange * 3600;
    final windowEndSecs = latestSecs - panSecs;
    // Wall-clock time at x == 0 (the latest reading), to label the X axis with
    // real times. x is hours relative to this, so wall(x) = anchor + x hours.
    final anchor = widget.sensorStart?.add(Duration(seconds: latestSecs));
    // Phase-shift X so full wall-clock hours land on integer x values (the axis
    // ticks): shift = the fractional-hour part of the latest reading's time.
    final shift = anchor == null
        ? 0.0
        : (anchor.minute * 60 + anchor.second) / 3600.0;
    final series = GlucoseChartSeries(
      entries: entries,
      latestSecs: latestSecs,
      cutoff: windowEndSecs - effectiveRange * 3600,
      windowEnd: windowEndSecs,
      shift: shift,
      glucose: glucose,
      colors: colors,
    );
    final bars = series.buildBars();
    // Dashed forecast line extending past the latest reading (only in the live
    // window — a forecast on a past interval makes no sense).
    final controller = context.watch<CgmController>();
    final showBand = context.watch<ProfilePredictionState>().band;
    final prediction = panWindows > 0
        ? (
            futureHours: 0.0,
            touchSpots: const <FlSpot>[],
            band: null as BetweenBarsData?,
          )
        : _addPredictionBar(
            bars,
            controller,
            entries,
            latestSecs,
            shift,
            glucose,
            showBand,
          );
    final futureHours = prediction.futureHours;
    // Transparent overlay owning touch — over the REAL readings AND the forecast
    // points, so scrubbing snaps to a single value in either region (not to the
    // zone bars, which share boundary points, or the interpolated crossings).
    _touchBarIndex = bars.length;
    bars.add(_touchBar([...series.realSpots, ...prediction.touchSpots]));
    // Meal overlay: a marker line per logged meal (drawn by GlucoseLineChart)
    // plus a transparent bar of tappable dots appended here, so a tap resolves
    // to a meal via its spot index.
    final mealMarkers = _buildMealMarkers(
      anchor,
      shift,
      effectiveRange,
      panSecs,
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
      '$latestSecs-${entries.length}-$effectiveRange-$panWindows'
      '-$predictionCount-${prediction.band != null}-${mealMarkers.length}',
    );
    GlucoseLineChart chart(double pulse) => GlucoseLineChart(
      key: key,
      bars: bars,
      betweenBars: [if (prediction.band != null) prediction.band!],
      touchBarIndex: _touchBarIndex,
      shift: shift,
      rangeHours: effectiveRange,
      anchor: anchor,
      glucose: glucose,
      colors: colors,
      onChartTouch: _onChartTouch,
      interactive: !widget.preview,
      minimal: widget.preview,
      minYmgdl: widget.minYmgdl,
      maxYmgdl: widget.maxYmgdl,
      highlightSpot: widget.preview ? highlightSpot : null,
      pulse: pulse,
      futureHours: futureHours,
      panHours: panSecs / 3600.0,
      mealMarkers: mealMarkers,
    );
    // Only the overview preview pulses; the detail page renders once (no per-
    // frame relayout of the full chart).
    if (!widget.preview) {
      return chart(0);
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => chart(_pulse.value),
    );
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
    final scheme = Theme.of(context).colorScheme;
    bars.add(_bandEdgeBar([anchor, ...spots.low]));
    bars.add(_bandEdgeBar([anchor, ...spots.high]));
    return BetweenBarsData(
      fromIndex: bars.length - 2,
      toIndex: bars.length - 1,
      color: scheme.onSurface.withValues(alpha: 0.12),
    );
  }

  /// An invisible band edge: it exists only to bound the fill, so it carries no
  /// stroke of its own. Curve settings mirror [_predictionBar] — a differently
  /// smoothed edge would drift away from the mean line it wraps.
  LineChartBarData _bandEdgeBar(List<FlSpot> spots) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.4,
      barWidth: 0,
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
    final scheme = Theme.of(context).colorScheme;
    final lineColor = scheme.onSurface.withValues(alpha: 0.5);
    final dotColor = HSLColor.fromColor(
      scheme.onSurface,
    ).withLightness(0.6).toColor();
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
    int effectiveRange,
    int panSecs,
  ) {
    if (!widget.showMeals || anchor == null || widget.meals.isEmpty) {
      return const [];
    }
    final panHours = panSecs / 3600.0;
    final minX = shift - effectiveRange - panHours - 0.5;
    final maxX = shift - panHours + 0.5;
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
    final scheme = Theme.of(context).colorScheme;
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
          color: context.warning,
          strokeColor: scheme.surface,
          strokeWidth: 2,
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
