import 'package:flutter/material.dart';
import 'package:insulink/src/analysis/ranges/glucose_band.dart';
import 'package:insulink/src/base/segment_bar.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:provider/provider.dart';

/// Time in range over the last 24 h: the in-range share large, low and high as
/// two small values beside it, and a low / in range / high bar underneath.
/// Reuses the analysis band logic.
class OverviewTimeInRange extends StatelessWidget {
  const OverviewTimeInRange({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final values = controller.archiveSince(const Duration(hours: 24)).values;
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }
    final bands = TimeInRangeBands(
      values: values,
      glucose: context.watch<ProfileGlucoseState>(),
      colors: Theme.of(context).extension<GlucoseColors>()!,
      coarse: true,
    ).build();
    if (bands.isEmpty) {
      return const SizedBox.shrink();
    }
    final (high, inRange, low) = (bands[0], bands[1], bands[2]);
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          _summary(context, inRange, low, high),
          SegmentBar(
            gap: 3,
            segments: [
              for (final band in [low, inRange, high])
                BarSegment(color: band.color, weight: band.fraction),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summary(
    BuildContext context,
    GlucoseBand inRange,
    GlucoseBand low,
    GlucoseBand high,
  ) {
    final muted = context.ink.muted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(_percent(inRange), style: InkText.bigValue),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            Locales.string(context, 'overview.in_range_window'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: InkText.label.copyWith(color: muted),
          ),
        ),
        _legend(low, muted),
        const SizedBox(width: 12),
        _legend(high, muted),
      ],
    );
  }

  Widget _legend(GlucoseBand band, Color muted) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        spacing: 5,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: band.color,
              shape: BoxShape.circle,
            ),
          ),
          Text(_percent(band), style: TextStyle(fontSize: 13, color: muted)),
        ],
      ),
    );
  }

  /// The band's percentage with the space German puts before the sign ("87 %").
  String _percent(GlucoseBand band) => band.pctLabel.replaceFirst('%', ' %');
}
