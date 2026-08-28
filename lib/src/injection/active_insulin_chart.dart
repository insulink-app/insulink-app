import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';

/// Graphs how the active insulin (IOB) rises at each bolus and decays away — the
/// sampled [curve] from [ActiveInsulin], with a marker on where "now" sits so the
/// past (measured decay) reads apart from the future (projected). X is minutes
/// since the first still-active dose; the labels map back to clock time.
class ActiveInsulinChart extends StatelessWidget {
  const ActiveInsulinChart({
    super.key,
    required this.points,
    required this.now,
  });

  final List<({DateTime at, double units})> points;
  final DateTime now;

  double get _spanMin =>
      points.last.at.difference(points.first.at).inSeconds / 60;

  double get _nowX => now.difference(points.first.at).inSeconds / 60;

  double get _maxY {
    final peak = points.fold(0.0, (max, p) => p.units > max ? p.units : max);
    return (peak * 1.15).clamp(1.0, double.infinity);
  }

  /// Two points is the least that can be a line, and everything below reads
  /// `points.first` and `points.last`.
  ///
  /// Guarded HERE rather than only at the call sites. A caller that forgot threw
  /// during layout and left behind the grey box its failed render was sitting
  /// in, which is a puzzling thing to be shown and a cheap thing to make
  /// impossible.
  bool get _isDrawable => points.length >= 2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_isDrawable) {
      return const SizedBox.shrink();
    }
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: _spanMin,
        minY: 0,
        maxY: _maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _maxY / 2,
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context, scheme),
        extraLinesData: _nowLine(scheme),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [_iobBar(scheme)],
      ),
      duration: Duration.zero,
    );
  }

  LineChartBarData _iobBar(ColorScheme scheme) {
    return LineChartBarData(
      spots: [
        for (final point in points)
          FlSpot(
            point.at.difference(points.first.at).inSeconds / 60,
            point.units,
          ),
      ],
      isCurved: true,
      curveSmoothness: 0.15,
      preventCurveOverShooting: true,
      barWidth: 2.5,
      color: scheme.primary,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.25),
            scheme.primary.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }

  /// The dashed "now" divider — decayed past to its left, projection to its right.
  ExtraLinesData _nowLine(ColorScheme scheme) {
    return ExtraLinesData(
      verticalLines: [
        VerticalLine(
          x: _nowX,
          color: scheme.onSurface.withValues(alpha: 0.35),
          strokeWidth: 1,
          dashArray: const [4, 4],
        ),
      ],
    );
  }

  FlTitlesData _titles(BuildContext context, ColorScheme scheme) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: _maxY / 2,
          getTitlesWidget: (value, _) => _axisText(
            scheme,
            Locales.string(
              context,
              'injection.bolus.value',
              params: [value.toStringAsFixed(1)],
            ),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          interval: (_spanMin / 4).clamp(1, double.infinity),
          getTitlesWidget: (value, _) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _axisText(scheme, _clock(context, value)),
          ),
        ),
      ),
    );
  }

  String _clock(BuildContext context, double minutesSinceStart) {
    final time = points.first.at.add(
      Duration(seconds: (minutesSinceStart * 60).round()),
    );
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(time));
  }

  Widget _axisText(ColorScheme scheme, String text) => Text(
    text,
    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
  );
}
