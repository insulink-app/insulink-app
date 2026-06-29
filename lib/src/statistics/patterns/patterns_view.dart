import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/statistics/patterns/hourly_glucose_pattern.dart';
import 'package:insulink/src/statistics/patterns/pattern_chart.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// "Patterns": average glucose by hour-of-day across the long-term archive, so
/// recurring daily highs/lows stand out. A neutral median-style line with a
/// shaded ±1 SD deviation band around it (à la FreeStyle Libre).
class PatternsView extends StatelessWidget {
  const PatternsView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<G7Controller>();
    final glucose = context.watch<ProfileGlucoseState>();
    final colors = Theme.of(context).extension<GlucoseColors>()!;

    // Long-term archive (spans sensor swaps): keyed by absolute epoch-minute, so
    // hour-of-day comes straight from the timestamp — no session start needed.
    final pattern = HourlyGlucosePattern(controller.statsArchive).build();
    if (pattern.isEmpty) {
      return Center(child: LocaleText('statistics.empty'));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(context),
          const SizedBox(height: 20),
          Expanded(child: _chart(pattern, glucose, colors)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _title(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocaleText(
          'statistics.patterns.title',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        LocaleText(
          'statistics.patterns.hint',
          style: TextStyle(
            fontSize: 12,
            color: onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _chart(
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
    return PatternChart(
      meanSpots: meanSpots,
      upperSpots: upperSpots,
      lowerSpots: lowerSpots,
      glucose: glucose,
      colors: colors,
    );
  }
}
