import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/analysis/ranges/glucose_band.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// Compact "time in range" for the overview: a single horizontal stacked bar
/// over the last 24 h with a small legend. Reuses the analysis band logic.
class OverviewTimeInRange extends StatelessWidget {
  const OverviewTimeInRange({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final glucose = context.watch<ProfileGlucoseState>();
    final colors = Theme.of(context).extension<GlucoseColors>()!;

    final values = controller.archiveSince(const Duration(hours: 24)).values;
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }
    // Ascending glucose (very low → very high), so the bar reads left to right.
    final bands = TimeInRangeBands(
      values: values,
      glucose: glucose,
      colors: colors,
      coarse: true,
    ).build().reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            LocaleText(
              'overview.time_in_range',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            LocaleText(
              'overview.time_in_range_window',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _bar(bands),
        const SizedBox(height: 12),
        _legend(context, bands),
      ],
    );
  }

  Widget _bar(List<GlucoseBand> bands) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 18,
        child: Row(
          children: [
            for (final band in bands)
              if (band.fraction > 0)
                Expanded(
                  flex: (band.fraction * 1000).round().clamp(1, 1000),
                  child: Container(color: band.color),
                ),
          ],
        ),
      ),
    );
  }

  /// One row per band, listed top → bottom (high → in range → low): the zone on
  /// the left, its percentage on the right.
  Widget _legend(BuildContext context, List<GlucoseBand> bands) {
    return Column(
      children: [for (final band in bands.reversed) _row(context, band)],
    );
  }

  Widget _row(BuildContext context, GlucoseBand band) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: band.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          LocaleText(band.labelKey, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Text(
            band.rangeLabel,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const Spacer(),
          Text(
            band.pctLabel,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
