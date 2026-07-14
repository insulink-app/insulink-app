import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/glucose_trend_icon.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// Compact current-glucose readout with a Phosphor trend arrow.
class OverviewCurrentValue extends StatelessWidget {
  const OverviewCurrentValue({
    super.key,
    required this.mgdl,
    required this.trendPerMin,
    this.stale = false,
  });

  final int? mgdl;
  final double? trendPerMin;

  /// The value/trend are NOT from a fresh live reading (cached on launch or from
  /// the synced archive) — shown grey so it reads as not-live.
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final glucose = context.watch<ProfileGlucoseState>();
    // The big headline uses its own per-theme palette (defined explicitly in
    // GlucoseColors): deeper on the light background, brighter on the dark one.
    final colors = Theme.of(context).brightness == Brightness.dark
        ? GlucoseColors.headlineDark
        : GlucoseColors.headlineLight;
    final value = mgdl;
    // A stale (cached / synced, not live) value is shown grey regardless of its
    // low/high zone, so it clearly reads as not-live.
    final color = (value == null || stale)
        ? Colors.grey
        : colors.forValue(value, glucose);
    final hasTrend = value != null && trendPerMin != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // No current value yet (e.g. just after a re-login/restore, awaiting the
        // first live reading) → a spinner where the number goes, while the chart
        // below still shows the known history.
        if (value == null)
          const SizedBox(
            height: 100,
            child: Center(child: CupertinoActivityIndicator(radius: 18)),
          )
        else
          Text(
            glucose.format(value),
            style: TextStyle(
              fontSize: 100,
              fontWeight: FontWeight.bold,
              height: 1,
              color: color,
            ),
          ),
        const SizedBox(width: 12),
        // Arrow sits up near the top of the number; unit + trend stack beneath.
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasTrend)
              GlucoseTrendIcon(perMin: trendPerMin!, color: color, size: 52),
            if (hasTrend)
              Text(
                '${glucose.formatTrend(trendPerMin!)}/min',
                style: TextStyle(fontSize: 10, color: Colors.grey[400]),
              ),
            Text(
              glucose.unit.label,
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ],
    );
  }
}
