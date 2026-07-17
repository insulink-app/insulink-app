import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/analysis/history/glucose_history_series.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Glucose over time across the selected window: a mean line bucketed by the
/// adaptive X-axis (hours / weekdays / days-of-month / months). Reads the
/// long-term archive so it spans sensor swaps.
class GlucoseHistoryView extends StatelessWidget {
  const GlucoseHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final glucose = context.watch<ProfileGlucoseState>();
    final colors = Theme.of(context).extension<GlucoseColors>()!;
    final series = GlucoseHistorySeries(
      controller.statsArchive,
      controller.statsSpan,
      glucose,
    );
    final spots = series.build();
    if (spots.isEmpty) {
      return const EmptyState(
        icon: PhosphorIconsBold.chartLineUp,
        titleKey: 'analysis.empty',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 20, 48),
      child: _Chart(
        spots: spots,
        starts: series.starts,
        bucket: series.bucket,
        glucose: glucose,
        colors: colors,
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({
    required this.spots,
    required this.starts,
    required this.bucket,
    required this.glucose,
    required this.colors,
  });

  final List<FlSpot> spots;
  final List<DateTime> starts;
  final HistoryBucket bucket;
  final ProfileGlucoseState glucose;
  final GlucoseColors colors;

  double get _maxY => glucose.toDisplay(300);
  double get _yInterval => glucose.unit == GlucoseUnit.mmol ? 3.0 : 50.0;

  /// Show roughly six X labels regardless of bucket count.
  double get _xInterval =>
      (starts.length / 6).ceilToDouble().clamp(1, double.infinity);

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (starts.length - 1).toDouble(),
        minY: 0,
        maxY: _maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _yInterval,
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context),
        extraLinesData: _targetLines(),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            preventCurveOverShooting: true,
            barWidth: 2.5,
            color: onSurface.withValues(alpha: 0.85),
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  FlTitlesData _titles(BuildContext context) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          interval: _yInterval,
          getTitlesWidget: (value, _) => _label(context, _formatY(value)),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: _xInterval,
          getTitlesWidget: (value, _) => _bottomLabel(context, value),
        ),
      ),
    );
  }

  Widget _bottomLabel(BuildContext context, double value) {
    final index = value.round();
    if (index < 0 || index >= starts.length) {
      return const SizedBox.shrink();
    }
    return _label(context, _formatX(context, starts[index]));
  }

  /// Localized tick text for a bucket start, per the chosen granularity.
  String _formatX(BuildContext context, DateTime time) {
    switch (bucket) {
      case HistoryBucket.hour:
        return '${time.hour}';
      case HistoryBucket.weekday:
        return Locales.string(context, 'date.weekday.${time.weekday}');
      case HistoryBucket.monthDay:
        return '${time.day}';
      case HistoryBucket.month:
        return Locales.string(context, 'date.month.${time.month}');
    }
  }

  String _formatY(double value) => glucose.unit == GlucoseUnit.mmol
      ? value.toStringAsFixed(0)
      : '${value.toInt()}';

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 10,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  ExtraLinesData _targetLines() {
    return ExtraLinesData(
      horizontalLines: [
        HorizontalLine(
          y: glucose.toDisplay(glucose.targetLow),
          color: colors.low.withValues(alpha: 0.4),
          strokeWidth: 1,
        ),
        HorizontalLine(
          y: glucose.toDisplay(glucose.targetHigh),
          color: colors.high.withValues(alpha: 0.4),
          strokeWidth: 1,
        ),
      ],
    );
  }
}
