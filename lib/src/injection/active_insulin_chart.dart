import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/injection/active_insulin_touch.dart';
import 'package:insulink/src/injection/insulin_on_board_curve.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulin_colors.dart';

/// Graphs how the active insulin (IOB) rises and decays away, stacked by where
/// it came from: the automation's rate at the bottom in the basal colour, its
/// micro boluses above in a lighter bolus colour, the user's own boluses on top.
/// The top edge is the total. A marker shows where "now" sits, so the past
/// (what was on board) reads apart from the future (what is left decaying). X is
/// minutes since the first sample; the labels map back to clock time.
class ActiveInsulinChart extends StatelessWidget {
  const ActiveInsulinChart({
    super.key,
    required this.points,
    required this.now,
  });

  final List<InsulinOnBoardSample> points;
  final DateTime now;

  /// How strongly the micro-bolus band is tinted against the bolus band above
  /// it: the same colour family, because both are boluses, told apart by weight.
  static const double microBolusTint = 0.45;

  double get _spanMin =>
      points.last.at.difference(points.first.at).inSeconds / 60;

  double get _nowX => now.difference(points.first.at).inSeconds / 60;

  double get _maxY {
    final peak = points.fold(0.0, (max, p) => p.total > max ? p.total : max);
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
        lineTouchData: ActiveInsulinTouch(points).data(context),
        lineBarsData: [
          _layer(
            (point) => point.rate,
            context.insulin.basal,
            fillsToAxis: true,
          ),
          _layer(
            (point) => point.rate + point.microBoluses,
            context.insulin.bolus,
          ),
          _layer((point) => point.total, context.insulin.bolus, outline: true),
        ],
        betweenBarsData: [
          BetweenBarsData(
            fromIndex: 0,
            toIndex: 1,
            color: context.insulin.bolus.withValues(alpha: microBolusTint),
          ),
          BetweenBarsData(
            fromIndex: 1,
            toIndex: 2,
            color: context.insulin.bolus.withValues(alpha: 0.25),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  /// One edge of the stack: the sum of every layer up to this one. Only the
  /// total carries a visible line; the lower edges show as the change of fill.
  /// The rate is the bottom layer and so fills down to the axis itself.
  LineChartBarData _layer(
    double Function(InsulinOnBoardSample point) height,
    Color color, {
    bool outline = false,
    bool fillsToAxis = false,
  }) {
    return LineChartBarData(
      spots: [
        for (final point in points)
          FlSpot(
            point.at.difference(points.first.at).inSeconds / 60,
            height(point),
          ),
      ],
      isCurved: true,
      curveSmoothness: 0.15,
      preventCurveOverShooting: true,
      barWidth: outline ? 2.5 : 0,
      color: color,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: fillsToAxis,
        color: color.withValues(alpha: 0.35),
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
              params: [sportDecimal(value, 1)],
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
