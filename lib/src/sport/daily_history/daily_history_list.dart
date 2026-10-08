import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/base/track_bar.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/daily_history/daily_metric.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:intl/intl.dart';

/// "Verlauf": the days newest first in ONE panel parted by lines, each with its
/// date (today in bold), a 64 px bar towards the goal and the value.
class DailyHistoryList extends StatelessWidget {
  const DailyHistoryList({super.key, required this.days, required this.metric});

  /// The visible days, newest first.
  final List<DailyValue> days;
  final DailyMetric metric;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: SectionHeader(titleKey: 'sport.weight.history'),
        ),
        InkPanel.list(rows: [for (final day in days) _row(context, day)]),
      ],
    );
  }

  Widget _row(BuildContext context, DailyValue day) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 58),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: InkSpace.panelPadding),
        child: Row(
          spacing: 14,
          children: [
            Expanded(child: _date(context, day.date)),
            if (metric.hasGoal) _bar(context, day.value),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 64),
              child: Text(
                metric.labeled(day.value),
                textAlign: TextAlign.right,
                style: InkText.rowTitle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _date(BuildContext context, DateTime date) {
    final colors = context.ink;
    if (DateUtils.isSameDay(date, DateTime.now())) {
      return Text(
        Locales.string(context, 'date.today'),
        style: InkText.row.copyWith(color: colors.text),
      );
    }
    final tag = Localizations.localeOf(context).toLanguageTag();
    return Text(
      DateFormat.MMMEd(tag).format(date),
      style: InkText.label.copyWith(fontSize: 15, color: colors.muted),
    );
  }

  Widget _bar(BuildContext context, double value) {
    final colors = context.ink;
    return SizedBox(
      width: 64,
      child: TrackBar(
        startFraction: 0,
        endFraction: metric.progress(value),
        height: 6,
        color: metric.reached(value)
            ? colors.accent
            : colors.accent.withValues(alpha: 0.55),
      ),
    );
  }
}
