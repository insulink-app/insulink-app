import 'package:flutter/material.dart';
import 'package:insulink/src/injection/active_insulin_chart.dart';
import 'package:insulink/src/injection/insulin_on_board_curve.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulin_colors.dart';

/// Names the bands of [ActiveInsulinChart], only those that appear in it, so a
/// day without any automation reads exactly as it did before there was one.
class ActiveInsulinLegend extends StatelessWidget {
  const ActiveInsulinLegend({super.key, required this.points});

  final List<InsulinOnBoardSample> points;

  bool _any(double Function(InsulinOnBoardSample point) part) =>
      points.any((point) => part(point) > 0);

  @override
  Widget build(BuildContext context) {
    final colors = context.insulin;
    final entries = [
      if (_any((point) => point.boluses))
        (key: 'overview.active_insulin.layer.boluses', color: colors.bolus),
      if (_any((point) => point.microBoluses))
        (
          key: 'overview.active_insulin.layer.micro_boluses',
          color: colors.bolus.withValues(
            alpha: ActiveInsulinChart.microBolusTint,
          ),
        ),
      if (_any((point) => point.rate))
        (key: 'overview.active_insulin.layer.rate', color: colors.basal),
    ];
    if (entries.length < 2) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        for (final entry in entries) _item(context, entry.key, entry.color),
      ],
    );
  }

  Widget _item(BuildContext context, String key, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        LocaleText(
          key,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
