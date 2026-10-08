import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/activity_bar_chart.dart';
import 'package:insulink/src/sport/daily_history/daily_metric.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The bars of the window across the full panel width, without a Y axis: the
/// legend above ("Ziel erreicht", the dashed goal line), days that reached the
/// goal in the accent and the others at 45 %.
class DailyHistoryChartCard extends StatelessWidget {
  const DailyHistoryChartCard({
    super.key,
    required this.days,
    required this.metric,
  });

  final List<DailyValue> days;
  final DailyMetric metric;

  @override
  Widget build(BuildContext context) {
    return InkPanel(
      radius: InkRadius.tile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (metric.hasGoal) ...[_legend(context), const SizedBox(height: 14)],
          SizedBox(height: 194, child: _chart(context)),
        ],
      ),
    );
  }

  Widget _chart(BuildContext context) {
    if (days.isEmpty) {
      return Center(child: LocaleText('daily_history.empty_range'));
    }
    return ActivityBarChart<DailyValue>(
      days: days,
      date: (day) => day.date,
      value: (day) => day.value,
      label: (day) => metric.labeled(day.value),
      color: context.ink.accent,
      goal: metric.hasGoal ? metric.goal : null,
      bare: true,
    );
  }

  Widget _legend(BuildContext context) {
    final colors = context.ink;
    final style = InkText.caption.copyWith(color: colors.muted);
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        _entry(
          _swatch(colors),
          LocaleText('daily_history.goal_reached', style: style),
        ),
        _entry(
          _dash(colors),
          Text(
            Locales.string(
              context,
              'daily_history.goal',
              params: [metric.labeled(metric.goal!)],
            ),
            style: style,
          ),
        ),
      ],
    );
  }

  Widget _entry(Widget mark, Widget label) =>
      Row(mainAxisSize: MainAxisSize.min, spacing: 7, children: [mark, label]);

  Widget _swatch(InsulinkColors colors) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: colors.accent,
      borderRadius: BorderRadius.circular(3),
    ),
  );

  Widget _dash(InsulinkColors colors) => Row(
    spacing: 2,
    children: [
      for (var dash = 0; dash < 4; dash++)
        Container(
          width: 3,
          height: 1.5,
          color: colors.text.withValues(alpha: 0.5),
        ),
    ],
  );
}
