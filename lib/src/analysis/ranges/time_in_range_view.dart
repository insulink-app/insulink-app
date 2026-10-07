import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/analysis/ranges/glucose_band.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// How the window split into the five glucose bands, in one panel: the
/// in-range share large on top, a vertical stacked bar on the left, and the
/// bands as rows with their bounds and share on the right.
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
      return const EmptyState(
        icon: PhosphorIconsBold.chartLineUp,
        titleKey: 'analysis.empty',
      );
    }
    final bands = TimeInRangeBands(
      values: values,
      glucose: glucose,
      colors: colors,
    ).build();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        InkSpace.panelMargin,
        8,
        InkSpace.panelMargin,
        120,
      ),
      child: InkPanel(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headline(context, bands),
            const SizedBox(height: 18),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 20,
                children: [
                  _StackedBar(bands: bands),
                  Expanded(
                    child: _Legend(bands: bands, unitLabel: glucose.unit.label),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "91 % im Zielbereich".
  Widget _headline(BuildContext context, List<GlucoseBand> bands) {
    final inRange = bands.firstWhere(
      (band) => band.labelKey == 'analysis.range.in_range',
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: 12,
      children: [
        Text(
          inRange.spacedPercent,
          style: InkText.bigValue.copyWith(fontSize: 44),
        ),
        Flexible(
          child: LocaleText(
            'analysis.range.in_range_share',
            style: InkText.label.copyWith(
              fontSize: 15,
              color: context.ink.muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// The share as the page writes it.
extension _SpacedPercent on GlucoseBand {
  /// "<1%" as "< 1 %", "4%" as "4 %": German spacing around the signs.
  String get spacedPercent =>
      pctLabel.replaceFirst('<', '< ').replaceFirst('%', ' %');
}

/// The bands as one 28 px column of segments with 3 px gaps, each as tall as
/// its share; a non-empty band keeps at least a sliver.
class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.bands});

  final List<GlucoseBand> bands;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final band in bands)
        if (band.fraction > 0) band,
    ];
    return SizedBox(
      width: 28,
      child: Column(
        spacing: 3,
        children: [
          for (final band in shown)
            Expanded(
              flex: (band.fraction * 1000).round().clamp(8, 1000),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: band.color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}

/// The bands as rows parted by thin lines: colour dot, name over bounds, share.
class _Legend extends StatelessWidget {
  const _Legend({required this.bands, required this.unitLabel});

  final List<GlucoseBand> bands;
  final String unitLabel;

  @override
  Widget build(BuildContext context) {
    final line = context.ink.line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < bands.length; index++) ...[
          if (index > 0) Divider(height: 1, thickness: 1, color: line),
          _row(context, bands[index]),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, GlucoseBand band) {
    final colors = context.ink;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        spacing: 14,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: band.color,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                LocaleText(band.labelKey, style: InkText.row),
                Text(
                  '${band.rangeLabel} $unitLabel',
                  style: InkText.caption.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
          Text(
            band.spacedPercent,
            style: InkText.rowTitle.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
