import 'package:flutter/material.dart';
import 'package:insulink/src/analysis/averages/glucose_summary.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// The stat tiles shared by the analysis tabs: [stats] laid out two per row.
///
/// Lives here rather than in the averages tab it started in, because the same
/// tile is what every other analysis has to say a number in.
class AnalysisStatTiles extends StatelessWidget {
  const AnalysisStatTiles({super.key, required this.stats});

  final List<GlucoseStat> stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < stats.length; index += 2)
          _StatRow(
            left: stats[index],
            right: index + 1 < stats.length ? stats[index + 1] : null,
          ),
      ],
    );
  }
}

/// A pair of stat tiles side by side. IntrinsicHeight gives the row a finite
/// height (the taller tile) so the two tiles can stretch to match — without it,
/// `stretch` inside the scroll view's unbounded height throws.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.left, this.right});

  final GlucoseStat left;

  /// Null on an odd last row: the tile keeps its half of the width rather than
  /// stretching, so a lone stat does not read as a different kind of card.
  final GlucoseStat? right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _StatTile(stat: left)),
            const SizedBox(width: 12),
            Expanded(
              child: right == null
                  ? const SizedBox.shrink()
                  : _StatTile(stat: right!),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final GlucoseStat stat;

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
