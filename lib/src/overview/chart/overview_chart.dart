import 'dart:collection';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/overview/chart/glucose_chart_series.dart';
import 'package:insulink/src/overview/chart/glucose_line_chart.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// fl_chart line graph of glucose vs. time (hours, 0 = latest reading).
class OverviewChart extends StatefulWidget {
  const OverviewChart({
    super.key,
    required this.byTime,
    this.sensorStart,
    this.preview = false,
    this.minYmgdl = 0,
    this.maxYmgdl = 300,
  });

  final SplayTreeMap<int, int> byTime;

  /// Preview mode (on the overview): hide the range selector and disable touch,
  /// so an outer tap handler can open the full-screen detail page.
  final bool preview;

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

  /// Drives the latest-reading dot's pulsing halo.
  late final AnimationController _pulse;

  /// Index of the transparent overlay bar that owns touch (so the haptic and
  /// tooltip ignore the per-zone colour bars + interpolated crossing points).
  int _touchBarIndex = 0;

  /// Spot index under the finger on the last touch event, so we only buzz once
  /// per data point as the finger moves across (and reset when it lifts off).
  int? _lastTouchedIndex;

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
    setState(() => _rangeHours = hours);
    _storage.write(key: _kRangeKey, value: '$hours');
  }

  /// Light haptic tick when the highlighted point changes while scrubbing. Use
  /// the overlay (real-reading) bar's spot, so movement is tracked per actual
  /// reading rather than per colour segment.
  void _onChartTouch(FlTouchEvent event, LineTouchResponse? response) {
    final spots = response?.lineBarSpots;
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
        Align(alignment: Alignment.centerLeft, child: _rangeSelector(context)),
        const SizedBox(height: 40),
        Expanded(child: _chart(byTime, glucose, colors)),
      ],
    );
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
      cutoff: latestSecs - effectiveRange * 3600,
      shift: shift,
      glucose: glucose,
      colors: colors,
    );
    final bars = series.buildBars();
    // Dashed forecast line extending past the latest reading (when enabled).
    final controller = context.watch<CgmController>();
    final prediction = _addPredictionBar(
      bars,
      controller,
      entries,
      latestSecs,
      shift,
      glucose,
    );
    final futureHours = prediction.futureHours;
    // Transparent overlay owning touch — over the REAL readings AND the forecast
    // points, so scrubbing snaps to a single value in either region (not to the
    // zone bars, which share boundary points, or the interpolated crossings).
    _touchBarIndex = bars.length;
    bars.add(_touchBar([...series.realSpots, ...prediction.touchSpots]));
    final highlightSpot = series.realSpots.isEmpty
        ? null
        : series.realSpots.last;
    // Remount on each data change so fl_chart renders the new data statically
    // instead of tweening between structurally-different bar lists — that lerp
    // flashes a malformed frame even with a zero-duration animation.
    final predictionCount = controller.predictionCurve?.length ?? 0;
    final key = ValueKey(
      '$latestSecs-${entries.length}-$effectiveRange-$predictionCount',
    );
    GlucoseLineChart chart(double pulse) => GlucoseLineChart(
      key: key,
      bars: bars,
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

  /// Appends the dashed forecast bar (anchored at the latest reading) and
  /// returns how many hours it extends past it (so the X axis can widen to fit)
  /// plus the future points, which the touch overlay also covers so they're
  /// hoverable. No forecast / no session clock → nothing added, 0 / empty.
  ({double futureHours, List<FlSpot> touchSpots}) _addPredictionBar(
    List<LineChartBarData> bars,
    CgmController controller,
    List<MapEntry<int, int>> entries,
    int latestSecs,
    double shift,
    ProfileGlucoseState glucose,
  ) {
    final curve = controller.predictionCurve;
    final base = controller.predictionBase;
    final start = widget.sensorStart;
    if (curve == null || base == null || start == null || entries.isEmpty) {
      return (futureHours: 0, touchSpots: const <FlSpot>[]);
    }
    final baseSecs = base.difference(start).inSeconds;
    final anchor = FlSpot(shift, glucose.toDisplay(entries.last.value));
    final future = [
      for (final point in curve)
        FlSpot(
          (baseSecs + point.offsetMin * 60 - latestSecs) / 3600.0 + shift,
          glucose.toDisplay(point.mgdl),
        ),
    ];
    bars.add(_predictionBar([anchor, ...future]));
    final lastSecs = baseSecs + curve.last.offsetMin * 60;
    return (
      futureHours: ((lastSecs - latestSecs) / 3600.0).clamp(0.0, 24.0),
      touchSpots: future,
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

  /// Segmented control to pick the visible time window.
  Widget _rangeSelector(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final hours in const [24, 12, 6]) _rangeChip(theme, hours),
        ],
      ),
    );
  }

  Widget _rangeChip(ThemeData theme, int hours) {
    final selected = _rangeHours == hours;
    return GestureDetector(
      onTap: () => _setRange(hours),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${hours}h',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
