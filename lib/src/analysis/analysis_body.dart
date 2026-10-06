import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/analysis/averages/average_view.dart';
import 'package:insulink/src/analysis/events/event_log_view.dart';
import 'package:insulink/src/analysis/forecast/forecast_accuracy_view.dart';
import 'package:insulink/src/analysis/history/glucose_history_view.dart';
import 'package:insulink/src/analysis/patterns/patterns_view.dart';
import 'package:insulink/src/analysis/range_selector.dart';
import 'package:insulink/src/analysis/ranges/time_in_range_view.dart';

class AnalysisBody extends AppPageBody {
  AnalysisBody({super.key})
    : super(
        name: "analysis.label",
        unselectedIcon: PhosphorIconsRegular.chartPieSlice,
        selectedIcon: PhosphorIconsFill.chartPieSlice,
      );

  @override
  Widget content(BuildContext context) {
    return const AnalysisBodyContent();
  }
}

/// One selectable analysis, shown as a top tab.
class _AnalysisTab {
  const _AnalysisTab(this.labelKey, this.view);
  final String labelKey;
  final Widget view;
}

class AnalysisBodyContent extends StatelessWidget {
  const AnalysisBodyContent({super.key});

  /// The analyses offered as top tabs. Add new ones here — the first one
  /// is the main time-in-range breakdown; the rest are placeholders for now.
  static const List<_AnalysisTab> _tabs = [
    _AnalysisTab('analysis.tab.ranges', TimeInRangeView()),
    _AnalysisTab('analysis.tab.patterns', PatternsView()),
    _AnalysisTab('analysis.tab.averages', AverageView()),
    _AnalysisTab('analysis.tab.history', GlucoseHistoryView()),
    _AnalysisTab('analysis.tab.events', EventLogView()),
    _AnalysisTab('analysis.tab.forecast', ForecastAccuracyView()),
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
          // active tab. Two rows so the tabs fit without overflowing.
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
            child: AnalysisRangeSelector(),
          ),
          Expanded(
            child: TabBarView(children: [for (final t in _tabs) t.view]),
          ),
        ],
      ),
    );
  }
}

/// The tab selector as two rows of pill segments (half the tabs each) driving
/// the surrounding [TabController] — so they fit without a scrolling or
/// overflowing single row. The active segment gets the filled primary pill.
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

  Widget _row(
    BuildContext context,
    TabController controller,
    int start,
    int end,
  ) {
    return Row(
      children: [
        for (var index = start; index < end; index++)
          Expanded(child: _segment(context, controller, index)),
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
          // Scaled down rather than clipped: a row holds four tabs since the
          // forecast one was added, and the longest German labels no longer fit
          // a quarter of a narrow screen at full size.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              labels[index],
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
