import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/analysis/history/glucose_history_series.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/analysis/analysis_chart_section.dart';
import 'package:insulink/src/analysis/glucose_band_chart.dart';

/// Glucose over time across the selected window: a mean line bucketed by the
/// adaptive X-axis (hours / weekdays / days-of-month / months). Reads the
/// long-term archive so it spans sensor swaps.
class GlucoseHistoryView extends StatelessWidget {
  const GlucoseHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final glucose = context.watch<ProfileGlucoseState>();
    final colors = Theme.of(context).extension<GlucoseColors>()!;
    final series = GlucoseHistorySeries(
      controller.statsArchive,
      controller.statsSpan,
      glucose,
    );
    final spots = series.build();
    if (spots.isEmpty) {
      return const EmptyState(
        icon: PhosphorIconsBold.chartLineUp,
        titleKey: 'analysis.empty',
      );
    }
    final title = switch (series.bucket) {
      HistoryBucket.hour => 'hour',
      HistoryBucket.month => 'month',
      _ => 'day',
    };
    final starts = series.starts;
    final every = (starts.length / 7).ceil().clamp(1, starts.length);
    return AnalysisChartSection(
      titleKey: 'analysis.history_chart.title_$title',
      hintKey: 'analysis.history_chart.hint_$title',
      chart: GlucoseBandChart(
        meanSpots: spots,
        upperSpots: series.upperSpots,
        lowerSpots: series.lowerSpots,
        glucose: glucose,
        colors: colors,
        minX: 0,
        maxX: (starts.length - 1).toDouble(),
        xInterval: 1,
        dots: spots.length <= 31,
        xLabel: (value) {
          final index = value.round();
          if (value != index || index % every != 0 || index >= starts.length) {
            return null;
          }
          return _label(context, series.bucket, starts[index]);
        },
      ),
    );
  }

  /// The tick label for a bucket: hour, weekday, day of month or month.
  String _label(BuildContext context, HistoryBucket bucket, DateTime time) {
    switch (bucket) {
      case HistoryBucket.hour:
        return '${time.hour}';
      case HistoryBucket.weekday:
        return Locales.string(context, 'date.weekday.${time.weekday}');
      case HistoryBucket.monthDay:
        return '${time.day}';
      case HistoryBucket.month:
        return Locales.string(context, 'date.month.${time.month}');
    }
  }
}
