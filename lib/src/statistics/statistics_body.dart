import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/statistics/average_view.dart';
import 'package:insulink/src/statistics/patterns_view.dart';
import 'package:insulink/src/statistics/time_in_range_view.dart';

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
    _StatisticTab('statistics.tab.averages', AverageView()),
    _StatisticTab('statistics.tab.patterns', PatternsView()),
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
          // active tab.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor),
              ),
              child: TabBar(
                isScrollable: false,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                splashBorderRadius: BorderRadius.circular(8),
                labelColor: Colors.white,
                unselectedLabelColor: theme.colorScheme.onSurface,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [
                  for (final t in _tabs)
                    Tab(
                      height: 38,
                      text: Locales.string(context, t.labelKey),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(children: [for (final t in _tabs) t.view]),
          ),
        ],
      ),
    );
  }
}
