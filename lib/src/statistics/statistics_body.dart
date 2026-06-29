import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/statistics/averages/average_view.dart';
import 'package:insulink/src/statistics/calendar/calendar_heatmap_view.dart';
import 'package:insulink/src/statistics/events/event_log_view.dart';
import 'package:insulink/src/statistics/history/glucose_history_view.dart';
import 'package:insulink/src/statistics/patterns/patterns_view.dart';
import 'package:insulink/src/statistics/range_selector.dart';
import 'package:insulink/src/statistics/ranges/time_in_range_view.dart';

class StatisticsBody extends AppPageBody {
  StatisticsBody({super.key})
    : super(
        name: "statistics.label",
        unselectedIcon: CupertinoIcons.chart_pie,
        selectedIcon: CupertinoIcons.chart_pie_fill,
      );

  @override
  Widget content(BuildContext context) {
    return const StatisticsBodyContent();
  }
}

/// One selectable statistic, shown as a top tab.
class _StatisticTab {
  const _StatisticTab(this.labelKey, this.view);
  final String labelKey;
  final Widget view;
}

class StatisticsBodyContent extends StatelessWidget {
  const StatisticsBodyContent({super.key});

  /// The statistics offered as top tabs. Add new analyses here — the first one
  /// is the main time-in-range breakdown; the rest are placeholders for now.
  static const List<_StatisticTab> _tabs = [
    _StatisticTab('statistics.tab.ranges', TimeInRangeView()),
    _StatisticTab('statistics.tab.patterns', PatternsView()),
    _StatisticTab('statistics.tab.averages', AverageView()),
    _StatisticTab('statistics.tab.history', GlucoseHistoryView()),
    _StatisticTab('statistics.tab.events', EventLogView()),
    _StatisticTab('statistics.tab.calendar', CalendarHeatmapView()),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: _tabs.length,
      child: Column(
        children: [
          // App-style segmented pill selector (mirrors the overview chart's
          // range selector): rounded track + a filled primary pill behind the
          // active tab. Two rows so four tabs fit without overflowing.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor),
              ),
              child: _TwoRowTabs(
                labels: [
                  for (final t in _tabs) Locales.string(context, t.labelKey),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: StatisticsRangeSelector(),
          ),
          Expanded(
            child: TabBarView(children: [for (final t in _tabs) t.view]),
          ),
        ],
      ),
    );
  }
}

/// The tab selector as two rows of pill segments (chunks of 2) driving the
/// surrounding [TabController] — so four tabs fit without a scrolling/overflowing
/// single row. The active segment gets the filled primary pill.
class _TwoRowTabs extends StatelessWidget {
  const _TwoRowTabs({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final split = (labels.length / 2).ceil();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(context, controller, 0, split),
            const SizedBox(height: 4),
            _row(context, controller, split, labels.length),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, TabController controller, int start, int end) {
    return Row(
      children: [
        for (var index = start; index < end; index++)
          Expanded(
            child: _segment(context, controller, index),
          ),
      ],
    );
  }

  Widget _segment(BuildContext context, TabController controller, int index) {
    final theme = Theme.of(context);
    final selected = controller.index == index;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: GestureDetector(
        onTap: () => controller.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            labels[index],
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.bold : FontWeight.w600,
              color: selected ? Colors.white : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
