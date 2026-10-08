import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/daily_history/daily_history_chart_card.dart';
import 'package:insulink/src/sport/daily_history/daily_history_header.dart';
import 'package:insulink/src/sport/daily_history/daily_history_list.dart';
import 'package:insulink/src/sport/daily_history/daily_history_stats.dart';
import 'package:insulink/src/sport/daily_history/daily_metric.dart';
import 'package:insulink/src/sport/sport_range_selector.dart';

/// The body of a daily-total history, laid out as the steps screen (43): head,
/// key figures, range picker, bars and the day list a page at a time. Shared by
/// steps, distance and calories, the nutrition boxes (bolus included) and the
/// Google Health metrics, so they only say what their days and goal are.
class DailyHistoryView extends StatefulWidget {
  const DailyHistoryView({super.key, required this.days, required this.metric});

  /// Every day with data, ascending, never empty.
  final List<DailyValue> days;
  final DailyMetric metric;

  @override
  State<DailyHistoryView> createState() => _DailyHistoryViewState();
}

class _DailyHistoryViewState extends State<DailyHistoryView> {
  static const int _page = 8;

  SportRange _range = const SportRange.preset(30);

  /// How many history rows are shown; "show more" adds a page.
  int _shown = _page;

  DailyMetric get _metric => widget.metric;

  List<DailyValue> _inRange() {
    final from = _range.startFrom(DateTime.now());
    final to = _range.endTo;
    return [
      for (final day in widget.days)
        if ((from == null || !day.date.isBefore(DateUtils.dateOnly(from))) &&
            (to == null || day.date.isBefore(to)))
          day,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ranged = _inRange();
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
      children: [
        _header(),
        if (ranged.isNotEmpty) ...[
          const SizedBox(height: 22),
          DailyHistoryStats(days: ranged, metric: _metric),
        ],
        const SizedBox(height: 26),
        SportRangeSelector(
          value: _range,
          onChanged: (range) => setState(() => _range = range),
        ),
        const SizedBox(height: 10),
        DailyHistoryChartCard(days: ranged, metric: _metric),
        ..._history(ranged),
      ],
    );
  }

  /// Today's total for a summed metric (0 before anything is logged), the
  /// latest day for a rate.
  Widget _header() {
    final latest = widget.days.last;
    if (!_metric.summed) {
      return DailyHistoryHeader(
        labelKey: 'sport.activity.detail.latest',
        value: latest.value,
        metric: _metric,
      );
    }
    final isToday = DateUtils.isSameDay(latest.date, DateTime.now());
    return DailyHistoryHeader(
      labelKey: 'date.today',
      value: isToday ? latest.value : 0,
      metric: _metric,
    );
  }

  List<Widget> _history(List<DailyValue> ranged) {
    if (ranged.isEmpty) {
      return const [];
    }
    return [
      DailyHistoryList(
        days: ranged.reversed.take(_shown).toList(),
        metric: _metric,
      ),
      if (ranged.length > _shown)
        TextButton(
          onPressed: () => setState(() => _shown += _page),
          child: LocaleText('nutrition.meals.show_more'),
        ),
    ];
  }
}
