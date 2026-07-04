import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/sport/sport_models.dart';

/// Daily values of an activity metric as bars (X = day, ascending). Expects
/// [days] already filtered by time window and sorted ascending. [value] pulls
/// the metric to display out of a day; [label] renders its tooltip text
/// (formatted value + unit).
///
/// Tapping/hovering a bar shows a value+date tooltip with a haptic tick per bar,
/// mirroring the overview glucose chart.
class ActivityBarChart extends StatefulWidget {
  const ActivityBarChart({
    super.key,
    required this.days,
    required this.value,
    required this.label,
    required this.color,
  });

  final List<DailyActivity> days;
  final double Function(DailyActivity day) value;
  final String Function(DailyActivity day) label;
  final Color color;

  @override
  State<ActivityBarChart> createState() => _ActivityBarChartState();
}

class _ActivityBarChartState extends State<ActivityBarChart> {
  /// Bar index under the finger on the last touch event, so we buzz once per bar
  /// as the finger moves across (and reset when it lifts off).
  int? _lastTouchedIndex;

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final locale = MaterialLocalizations.of(context);
    final maxY = days.map(widget.value).fold<double>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY <= 0 ? 1 : maxY * 1.15,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: _touchData(context, locale),
        titlesData: _titles(locale),
        barGroups: [
          for (var index = 0; index < days.length; index++)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: widget.value(days[index]),
                  color: widget.color,
                  width: (260 / days.length).clamp(2, 14).toDouble(),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
              ],
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  BarTouchData _touchData(BuildContext context, MaterialLocalizations locale) {
    final theme = Theme.of(context);
    return BarTouchData(
      touchCallback: _onTouch,
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => theme.colorScheme.inverseSurface,
        tooltipBorderRadius: BorderRadius.circular(8),
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          final day = widget.days[group.x];
          return BarTooltipItem(
            widget.label(day),
            TextStyle(
              color: theme.colorScheme.onInverseSurface,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            children: [
              TextSpan(
                text: '\n${locale.formatShortDate(day.date)}',
                style: TextStyle(
                  color: theme.colorScheme.onInverseSurface.withValues(
                    alpha: 0.7,
                  ),
                  fontWeight: FontWeight.normal,
                  fontSize: 11,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Light haptic tick when the highlighted bar changes while scrubbing.
  void _onTouch(FlTouchEvent event, BarTouchResponse? response) {
    final index = response?.spot?.touchedBarGroupIndex;
    if (!event.isInterestedForInteractions || index == null) {
      _lastTouchedIndex = null;
      return;
    }
    if (index != _lastTouchedIndex) {
      _lastTouchedIndex = index;
      HapticFeedback.selectionClick();
    }
  }

  FlTitlesData _titles(MaterialLocalizations locale) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 42,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(
              value >= 1000
                  ? '${(value / 1000).toStringAsFixed(0)}k'
                  : value.toStringAsFixed(0),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index != 0 && index != widget.days.length - 1) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
              child: Text(
                locale.formatShortDate(widget.days[index].date),
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            );
          },
        ),
      ),
    );
  }
}
