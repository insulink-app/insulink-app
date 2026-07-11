import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/analysis/ranges/glucose_band.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// Dexcom-style "time in ranges": a single vertical stacked bar whose segments
/// are sized by the share of readings in each glucose band, with the band name,
/// its bounds and the percentage listed to the right.
class TimeInRangeView extends StatelessWidget {
  const TimeInRangeView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final glucose = context.watch<ProfileGlucoseState>();
    final colors = Theme.of(context).extension<GlucoseColors>()!;

    // Long-term archive (spans sensor swaps), not the current-session cache.
    final values = controller.statsArchive.values;
    if (values.isEmpty) {
      return const EmptyState(icon: Icons.insights_rounded, titleKey: 'analysis.empty');
    }
    final bands = TimeInRangeBands(
      values: values,
      glucose: glucose,
      colors: colors,
    ).build();

    // Sits near the top (not stretched over the whole page) and is centred
    // horizontally with a comfortable max width on wider screens.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SizedBox(
            height: 260,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StackedBar(bands: bands),
                const SizedBox(width: 24),
                Expanded(
                  child: _Legend(bands: bands, unitLabel: glucose.unit.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The single stacked bar — one coloured segment per band, sized by share.
class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.bands});

  final List<GlucoseBand> bands;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            for (final band in bands)
              if (band.fraction > 0)
                Expanded(
                  // Per-mille flex keeps the proportions; clamp to 1 so a tiny
                  // but non-zero band stays visible as a sliver.
                  flex: (band.fraction * 1000).round().clamp(1, 1000),
                  child: Container(color: band.color),
                ),
          ],
        ),
      ),
    );
  }
}

/// The right-hand legend: band name + bounds + percentage, one row per band,
/// spread over the full height so each roughly tracks its bar segment.
class _Legend extends StatelessWidget {
  const _Legend({required this.bands, required this.unitLabel});

  final List<GlucoseBand> bands;
  final String unitLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final band in bands) _row(context, band)],
    );
  }

  Widget _row(BuildContext context, GlucoseBand band) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: band.color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _labels(context, band)),
        const SizedBox(width: 8),
        Text(
          band.pctLabel,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _labels(BuildContext context, GlucoseBand band) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LocaleText(
          band.labelKey,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        Text(
          '${band.rangeLabel} $unitLabel',
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
