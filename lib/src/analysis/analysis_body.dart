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
import 'package:insulink/src/base/pill_scroll_row.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

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

  /// The page title, the analyses as a scrolling row of pills, the window
  /// picker, and the selected analysis. The pills drive the same tab
  /// controller the views swipe with.
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              InkSpace.page,
              4,
              InkSpace.page,
              14,
            ),
            child: LocaleText(
              'analysis.label',
              style: InkText.bigValue.copyWith(fontSize: 30),
            ),
          ),
          const _AnalysisPills(tabs: _tabs),
          const SizedBox(height: 12),
          const AnalysisRangeSelector(),
          const SizedBox(height: 4),
          Expanded(
            child: TabBarView(children: [for (final tab in _tabs) tab.view]),
          ),
        ],
      ),
    );
  }
}

/// The analyses as [PillScrollRow] pills, kept in step with the tab
/// controller both ways: a tap animates to the view, a swipe lights the pill.
class _AnalysisPills extends StatelessWidget {
  const _AnalysisPills({required this.tabs});

  final List<_AnalysisTab> tabs;

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => PillScrollRow<int>(
        selected: controller.index,
        onChanged: controller.animateTo,
        options: [
          for (var index = 0; index < tabs.length; index++)
            (
              value: index,
              label: Locales.string(context, tabs[index].labelKey),
            ),
        ],
      ),
    );
  }
}
