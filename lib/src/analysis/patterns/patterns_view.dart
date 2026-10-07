import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/analysis/patterns/hourly_glucose_pattern.dart';
import 'package:insulink/src/analysis/analysis_chart_section.dart';
import 'package:insulink/src/analysis/glucose_band_chart.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/localization/locales.dart';

/// "Patterns": average glucose by hour-of-day across the long-term archive, so
/// recurring daily highs/lows stand out. A neutral median-style line with a
/// shaded ±1 SD deviation band around it (à la FreeStyle Libre).
class PatternsView extends StatelessWidget {
  const PatternsView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final glucose = context.watch<ProfileGlucoseState>();
    final colors = Theme.of(context).extension<GlucoseColors>()!;

    // Long-term archive (spans sensor swaps): keyed by absolute epoch-minute, so
    // hour-of-day comes straight from the timestamp — no session start needed.
    final pattern = HourlyGlucosePattern(controller.statsArchive).build();
    if (pattern.isEmpty) {
      return const EmptyState(
        icon: PhosphorIconsBold.chartLineUp,
        titleKey: 'analysis.empty',
      );
    }

    return AnalysisChartSection(
      titleKey: 'analysis.patterns.title',
      hintKey: 'analysis.patterns.hint',
      withKey: true,
      chart: _chart(context, pattern, glucose, colors),
    );
  }

  Widget _chart(
    BuildContext context,
    List<({int hour, double mean, double sd})> pattern,
    ProfileGlucoseState glucose,
    GlucoseColors colors,
  ) {
    final meanSpots = <FlSpot>[];
    final upperSpots = <FlSpot>[];
    final lowerSpots = <FlSpot>[];
    for (final point in pattern) {
      final hourX = point.hour.toDouble();
      meanSpots.add(FlSpot(hourX, glucose.toDisplay(point.mean.round())));
      upperSpots.add(
        FlSpot(
          hourX,
          glucose.toDisplay((point.mean + point.sd).round().clamp(0, 300)),
        ),
      );
      lowerSpots.add(
        FlSpot(
          hourX,
          glucose.toDisplay((point.mean - point.sd).round().clamp(0, 300)),
        ),
      );
    }
    return GlucoseBandChart(
      meanSpots: meanSpots,
      upperSpots: upperSpots,
      lowerSpots: lowerSpots,
      glucose: glucose,
      colors: colors,
      minX: 0,
      maxX: 23,
      xInterval: 6,
      xLabel: (hour) => hour % 6 == 0 && hour < 23
          ? Locales.string(
              context,
              'overview.chart.hour',
              params: ['${hour.toInt()}'],
            )
          : null,
    );
  }
}
