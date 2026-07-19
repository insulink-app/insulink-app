import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/stats/sport_stat_format.dart';
import 'package:insulink/src/sport/stats/sport_stats.dart';

/// One exercise's progression: its best-set score over time, so a plateau or a
/// steady climb is visible at a glance, plus its session/set/best totals.
class ExerciseStatDetailPage extends StatelessWidget {
  const ExerciseStatDetailPage({super.key, required this.stat});

  final ExerciseStat stat;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(stat.exercise.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 64),
        children: [
          Row(
            children: [
              Expanded(
                child: _tile(
                  context,
                  'sport.stats.total_sessions',
                  '${stat.sessions.length}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _tile(
                  context,
                  'sport.stats.total_sets',
                  '${stat.totalSets}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _tile(
                  context,
                  'sport.stats.best',
                  formatScore(context, stat.best, stat.exercise.kind),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          LocaleText(
            'sport.stats.progression',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (stat.sessions.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: LocaleText(
                  'sport.stats.not_enough_data',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            )
          else
            SizedBox(height: 240, child: _chart(context)),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String labelKey, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocaleText(
            labelKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _chart(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spots = [
      for (var index = 0; index < stat.sessions.length; index++)
        FlSpot(index.toDouble(), stat.sessions[index].best),
    ];
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 34),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              minIncluded: false,
              maxIncluded: false,
              getTitlesWidget: (value, _) => _dateLabel(context, value),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItems: (touched) => [
              for (final spot in touched)
                LineTooltipItem(
                  formatScore(context, spot.y, stat.exercise.kind),
                  TextStyle(
                    color: scheme.onInverseSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            preventCurveOverShooting: true,
            barWidth: 2.5,
            color: scheme.primary,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }

  /// The date of the session at the tick's integer index (dd.MM.), or empty for
  /// a fractional tick between sessions.
  Widget _dateLabel(BuildContext context, double value) {
    final index = value.round();
    if ((value - index).abs() > 0.01 ||
        index < 0 ||
        index >= stat.sessions.length) {
      return const SizedBox.shrink();
    }
    final date = DateTime.fromMillisecondsSinceEpoch(stat.sessions[index].atMs);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '${date.day}.${date.month}.',
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
