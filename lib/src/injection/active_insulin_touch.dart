import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/injection/insulin_on_board_curve.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';

/// What a finger on the active-insulin graph reads out: the time, the total and
/// the part each layer contributes at that moment.
///
/// The graph draws three stacked lines, all touched at once. Only the top one,
/// the total, carries the tooltip and the marker; the other two return nothing,
/// so one finger gives one readout rather than three.
class ActiveInsulinTouch {
  const ActiveInsulinTouch(this.points);

  final List<InsulinOnBoardSample> points;

  LineTouchData data(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => scheme.inverseSurface,
        tooltipBorderRadius: BorderRadius.circular(8),
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        maxContentWidth: 180,
        getTooltipItems: (spots) => [
          for (final spot in spots)
            _isTotal(spot.bar) ? _readout(context, spot.spotIndex) : null,
        ],
      ),
      getTouchedSpotIndicator: (bar, indexes) => [
        for (final _ in indexes) _isTotal(bar) ? _marker(scheme) : null,
      ],
    );
  }

  /// The total is the only stacked line drawn with a visible width.
  bool _isTotal(LineChartBarData bar) => bar.barWidth > 0;

  TouchedSpotIndicatorData _marker(ColorScheme scheme) {
    return TouchedSpotIndicatorData(
      FlLine(
        color: scheme.onSurface.withValues(alpha: 0.35),
        strokeWidth: 1.5,
        dashArray: const [4, 4],
      ),
      FlDotData(
        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
          radius: 4,
          color: scheme.onSurface,
          strokeColor: scheme.surface,
          strokeWidth: 1.5,
        ),
      ),
    );
  }

  LineTooltipItem _readout(BuildContext context, int index) {
    final scheme = Theme.of(context).colorScheme;
    final point = points[index];
    final style = TextStyle(
      fontSize: 12,
      color: scheme.onInverseSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final parts = [
      ('overview.active_insulin.layer.boluses', point.boluses),
      ('overview.active_insulin.layer.micro_boluses', point.microBoluses),
      ('overview.active_insulin.layer.rate', point.rate),
    ];
    return LineTooltipItem(
      '${_clock(context, point.at)}\n',
      style.copyWith(fontWeight: FontWeight.w700),
      textAlign: TextAlign.start,
      children: [
        TextSpan(
          text: _line(
            context,
            'overview.active_insulin.layer.total',
            point.total,
          ),
          style: style.copyWith(fontWeight: FontWeight.w700),
        ),
        for (final (key, units) in parts)
          if (units > 0.005)
            TextSpan(text: '\n${_line(context, key, units)}', style: style),
      ],
    );
  }

  String _line(BuildContext context, String key, double units) {
    final value = Locales.string(
      context,
      'injection.bolus.value',
      params: [sportDecimal(units, 2)],
    );
    return '${Locales.string(context, key)}  $value';
  }

  String _clock(BuildContext context, DateTime at) {
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(at));
  }
}
