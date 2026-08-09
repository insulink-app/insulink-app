import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Daily values of a metric as bars (X = day, ascending). Expects [days] already
/// filtered by time window and sorted ascending. [date] pulls each entry's day,
/// [value] the metric to display, and [label] its tooltip text (formatted value
/// + unit). Generic so both the sport and the Google Health detail pages share it.
///
/// Tapping/hovering a bar shows a value+date tooltip with a haptic tick per bar,
/// mirroring the overview glucose chart.
///
/// [baseline] is where the bars start. It stays 0 for counted metrics (steps,
/// calories) — shortening those bars would misstate them. It is raised only for a
/// measurement with a physiological floor, where a zero baseline makes every bar
/// look identical: an HbA1c of 6.8 and 7.4 differ by 8 % of a 0-based bar but by
/// half a 4-based one. [decimals] follows, since such a value needs its axis
/// labelled finer than whole numbers.
class ActivityBarChart<T> extends StatefulWidget {
  const ActivityBarChart({
    super.key,
    required this.days,
    required this.date,
    required this.value,
    required this.label,
    required this.color,
    this.baseline = 0,
    this.decimals = 0,
  });

  final List<T> days;
  final DateTime Function(T day) date;
  final double Function(T day) value;
  final String Function(T day) label;
  final Color color;
  final double baseline;
  final int decimals;

  @override
  State<ActivityBarChart<T>> createState() => _ActivityBarChartState<T>();
}

class _ActivityBarChartState<T> extends State<ActivityBarChart<T>> {
  /// Bar index under the finger on the last touch event, so we buzz once per bar
  /// as the finger moves across (and reset when it lifts off).
  int? _lastTouchedIndex;

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final locale = MaterialLocalizations.of(context);
    final maxY = days
        .map(widget.value)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        minY: widget.baseline,
        maxY: maxY <= widget.baseline
            ? widget.baseline + 1
            : widget.baseline + (maxY - widget.baseline) * 1.15,
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
                  fromY: widget.baseline,
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
                text: '\n${locale.formatShortDate(widget.date(day))}',
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
                  : value.toStringAsFixed(widget.decimals),
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
                locale.formatShortDate(widget.date(widget.days[index])),
                style: TextStyle(
                  fontSize: 9,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
