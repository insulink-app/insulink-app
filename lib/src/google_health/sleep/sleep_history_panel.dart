import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:intl/intl.dart';

/// The nights as a list in one panel, newest first: the day, a small bar of the
/// night's length, and the length in bold. Shows a page at a time behind a
/// "show more".
class SleepHistoryPanel extends StatefulWidget {
  const SleepHistoryPanel({super.key, required this.nights});

  /// Ascending by date, as the archive keeps them.
  final List<GoogleHealthDay> nights;

  @override
  State<SleepHistoryPanel> createState() => _SleepHistoryPanelState();
}

class _SleepHistoryPanelState extends State<SleepHistoryPanel> {
  static const int _page = 8;

  /// A bar reaches the end at ten hours, or at the longest night if longer.
  static const int _fullBarMinutes = 600;

  int _shown = _page;

  @override
  Widget build(BuildContext context) {
    final newestFirst = widget.nights.reversed.toList();
    final visible = newestFirst.take(_shown).toList();
    final longest = newestFirst
        .map(_minutes)
        .fold<int>(_fullBarMinutes, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkPanel.list(
          rows: [for (final night in visible) _row(context, night, longest)],
        ),
        if (newestFirst.length > _shown)
          TextButton(
            onPressed: () => setState(() => _shown += _page),
            style: TextButton.styleFrom(foregroundColor: context.ink.accent),
            child: Text(
              Locales.string(context, 'google_health.sleep_page.show_more'),
            ),
          ),
      ],
    );
  }

  int _minutes(GoogleHealthDay night) =>
      night.value(GoogleHealthMetric.sleep)!.round();

  Widget _row(BuildContext context, GoogleHealthDay night, int longest) {
    final colors = context.ink;
    final minutes = _minutes(night);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 58),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          spacing: 12,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                _day(context, night.date),
                style: InkText.body.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colors.muted,
                ),
              ),
            ),
            Expanded(child: _bar(colors, minutes / longest)),
            SizedBox(
              width: 96,
              child: Text(
                formatSleepDuration(minutes),
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.end,
                style: InkText.rowTitle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Heute" for last night, otherwise the weekday and the date.
  String _day(BuildContext context, DateTime date) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(date, now)) {
      return Locales.string(context, 'date.today');
    }
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.MMMEd(locale).format(date);
  }

  Widget _bar(InsulinkColors colors, double share) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 6,
        color: colors.line,
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: share.clamp(0.0, 1.0),
          heightFactor: 1,
          child: ColoredBox(color: colors.accent.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}
