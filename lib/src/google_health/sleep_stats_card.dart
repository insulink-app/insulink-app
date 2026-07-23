import 'package:flutter/material.dart';

import '../localization/locale_text.dart';
import '../localization/locales.dart';
import 'google_health_models.dart';
import 'sleep_metrics.dart';
import 'sleep_stat_bar.dart';
import 'sleep_targets_state.dart';

/// The night's derived quality figures: a headline sleep index (0–100) and the
/// four target bars (time to deep sleep, deep sleep, restlessness, interruptions),
/// each with its configured target window as a dashed box.
class SleepStatsCard extends StatelessWidget {
  const SleepStatsCard({
    super.key,
    required this.stages,
    required this.timeline,
    required this.targets,
  });

  final SleepStages stages;
  final List<SleepSegment>? timeline;
  final SleepTargets targets;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final metrics = SleepMetrics.of(stages, timeline);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocaleText(
            'google_health.sleep_stats.index',
            style: TextStyle(
                fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          Text(
            '${metrics.sleepIndex}',
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Divider(color: scheme.onSurface.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 16),
          SleepStatBar(
            label: Locales.string(
                context, 'google_health.sleep_stats.time_to_solid'),
            valueText: _minutes(metrics.timeToSolidMinutes),
            value: metrics.timeToSolidMinutes ?? 0,
            targetMin: targets.timeToSolid.min,
            targetMax: targets.timeToSolid.max,
          ),
          SleepStatBar(
            label: Locales.string(context, 'google_health.sleep_stats.deep'),
            valueText: formatSleepMinutes(metrics.deepMinutes),
            value: metrics.deepMinutes,
            targetMin: targets.deep.min,
            targetMax: targets.deep.max,
          ),
          SleepStatBar(
            label: Locales.string(
                context, 'google_health.sleep_stats.interruption'),
            valueText: formatSleepMinutes(metrics.interruptionMinutes),
            value: metrics.interruptionMinutes,
            targetMin: targets.interruption.min,
            targetMax: targets.interruption.max,
          ),
        ],
      ),
    );
  }

  String _minutes(int? value) => value == null ? '–' : formatSleepMinutes(value);
}
