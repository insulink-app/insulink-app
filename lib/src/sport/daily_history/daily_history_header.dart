import 'package:flutter/material.dart';
import 'package:insulink/src/base/track_bar.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/daily_history/daily_metric.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The open head of a daily history, laid out like the weight page: the label,
/// the value large with "von {goal}" beside it, the percentage on the right and
/// an 8 px bar towards the goal underneath. Without a goal only the unit
/// follows the value.
class DailyHistoryHeader extends StatelessWidget {
  const DailyHistoryHeader({
    super.key,
    required this.labelKey,
    required this.value,
    required this.metric,
  });

  final String labelKey;
  final double value;
  final DailyMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocaleText(
            labelKey,
            style: InkText.label.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 4),
          _valueRow(context, colors),
          if (metric.hasGoal) ...[
            const SizedBox(height: 14),
            TrackBar(
              startFraction: 0,
              endFraction: metric.progress(value),
              color: colors.accent,
            ),
          ],
        ],
      ),
    );
  }

  Widget _valueRow(BuildContext context, InsulinkColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          metric.format(value),
          style: InkText.bigValue.copyWith(fontSize: 56, letterSpacing: -2),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            _trailing(context),
            style: InkText.label.copyWith(fontSize: 16, color: colors.muted),
          ),
        ),
        if (metric.hasGoal) ...[
          const Spacer(),
          Text(
            Locales.string(
              context,
              'daily_history.percent',
              params: ['${(value / metric.goal! * 100).round()}'],
            ),
            style: InkText.label.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.accentText,
            ),
          ),
        ],
      ],
    );
  }

  String _trailing(BuildContext context) => metric.hasGoal
      ? Locales.string(
          context,
          'daily_history.of',
          params: [metric.labeled(metric.goal!)],
        )
      : metric.unit ?? '';
}
