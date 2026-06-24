import 'dart:collection';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/overview/glucose_chart_series.dart';
import 'package:insulink/src/overview/glucose_line_chart.dart';
import 'package:insulink/src/profile/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// fl_chart line graph of glucose vs. time (hours, 0 = latest reading).
class OverviewChart extends StatefulWidget {
  const OverviewChart({super.key, required this.byTime, this.sensorStart});

  final SplayTreeMap<int, int> byTime;

  /// Wall-clock time the session started (`secsSinceStart == 0`). Lets the X
  /// axis show real clock times instead of hours-ago offsets.
  final DateTime? sensorStart;

  @override
  State<OverviewChart> createState() => _OverviewChartState();
}

class _OverviewChartState extends State<OverviewChart> {
  static const _kRangeKey = 'chart_range_hours';
  static const _storage = FlutterSecureStorage();

  /// Visible time window in hours (selectable: 6 / 12 / 24). Persisted.
  int _rangeHours = 24;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(alignment: Alignment.centerLeft, child: _rangeSelector(context)),
        const SizedBox(height: 20),
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
      cutoff: latestSecs - _rangeHours * 3600,
      shift: shift,
      glucose: glucose,
      colors: colors,
    );
    final bars = series.buildBars();
    // Transparent overlay over only the REAL readings: it owns touch, so the
    // tooltip + indicator snap to a single actual value instead of every zone
    // bar (which share boundary points) and the interpolated crossings.
    _touchBarIndex = bars.length;
    bars.add(_touchBar(series.realSpots));
    return GlucoseLineChart(
      bars: bars,
      touchBarIndex: _touchBarIndex,
      shift: shift,
      rangeHours: _rangeHours,
      anchor: anchor,
      glucose: glucose,
      colors: colors,
      onChartTouch: _onChartTouch,
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
