import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/profile_glucose_state.dart';
import 'package:provider/provider.dart';

/// A single computed statistic shown as a tile.
class _Stat {
  const _Stat(this.labelKey, this.value, this.unit);
  final String labelKey;
  final String value;
  final String unit;
}

/// Summary glucose statistics over the cached history: average, GMI (estimated
/// HbA1c), variability (CV), standard deviation and the extremes.
class AverageView extends StatelessWidget {
  const AverageView({super.key});

  @override
  Widget build(BuildContext context) {
    final g7 = context.watch<G7Controller>();
    final s = context.watch<ProfileGlucoseState>();

    // Long-term archive (spans sensor swaps), not the current-session cache.
    final values = g7.archiveSince(G7Controller.statsWindow).values.toList();
    if (values.isEmpty) {
      return Center(child: LocaleText('statistics.empty'));
    }

    final n = values.length;
    final mean = values.reduce((a, b) => a + b) / n;
    final variance =
        values.fold<double>(0, (acc, v) => acc + math.pow(v - mean, 2)) / n;
    final sd = math.sqrt(variance);
    final cv = mean == 0 ? 0.0 : sd / mean * 100;
    // Standard CGM GMI formula (estimated A1c) — always a percentage.
    final gmi = 3.31 + 0.02392 * mean;
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);

    final unit = s.unit.label;
    final stats = <_Stat>[
      _Stat('statistics.avg.mean', s.format(mean.round()), unit),
      _Stat('statistics.avg.gmi', gmi.toStringAsFixed(1), '%'),
      _Stat('statistics.avg.cv', cv.toStringAsFixed(1), '%'),
      _Stat('statistics.avg.sd', s.format(sd.round()), unit),
      _Stat('statistics.avg.max', s.format(maxV), unit),
      _Stat('statistics.avg.min', s.format(minV), unit),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              for (var i = 0; i < stats.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  // IntrinsicHeight gives the row a finite height (the taller
                  // tile) so the two tiles can stretch to match — without it,
                  // `stretch` inside the scroll view's unbounded height throws.
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _StatTile(stat: stats[i])),
                        const SizedBox(width: 12),
                        Expanded(child: _StatTile(stat: stats[i + 1])),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LocaleText(
            stat.labelKey,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                stat.value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                stat.unit,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
