import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// Compact current-glucose readout with a Cupertino trend arrow.
class OverviewCurrentValue extends StatelessWidget {
  const OverviewCurrentValue({
    super.key,
    required this.mgdl,
    required this.trendPerMin,
  });

  final int? mgdl;
  final double? trendPerMin;

  /// Cupertino arrow for the per-minute trend (5 directional buckets; the exact
  /// rate is shown as text alongside).
  IconData _arrow(double perMin) {
    if (perMin >= 2) {
      return CupertinoIcons.arrow_up;
    }
    if (perMin >= 1) {
      return CupertinoIcons.arrow_up_right;
    }
    if (perMin > -1) {
      return CupertinoIcons.arrow_right;
    }
    if (perMin > -2) {
      return CupertinoIcons.arrow_down_right;
    }
    return CupertinoIcons.arrow_down;
  }

  Color _color(int mgdl, ProfileGlucoseState glucose, GlucoseColors colors) {
    if (mgdl < glucose.targetLow) {
      return colors.low;
    }
    if (mgdl > glucose.targetHigh) {
      return colors.high;
    }
    return colors.inRange;
  }

  @override
  Widget build(BuildContext context) {
    final glucose = context.watch<ProfileGlucoseState>();
    // The big headline uses its own per-theme palette (defined explicitly in
    // GlucoseColors): deeper on the light background, brighter on the dark one.
    final colors = Theme.of(context).brightness == Brightness.dark
        ? GlucoseColors.headlineDark
        : GlucoseColors.headlineLight;
    final value = mgdl;
    final color = value == null ? Colors.grey : _color(value, glucose, colors);
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
            if (hasTrend) ...[
              Icon(_arrow(trendPerMin!), size: 52, color: color),
            ],
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
