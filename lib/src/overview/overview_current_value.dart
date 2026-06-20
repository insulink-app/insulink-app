import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/profile/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// Compact current-glucose readout with a Cupertino trend arrow.
class OverviewCurrentValue extends StatelessWidget {
  const OverviewCurrentValue({
    super.key,
    required this.mgdl,
    required this.trendPerMin,
    required this.busy,
  });

  final int? mgdl;
  final double? trendPerMin;
  final bool busy;

  /// Cupertino arrow for the per-minute trend (5 directional buckets; the exact
  /// rate is shown as text alongside).
  IconData _arrow(double perMin) {
    if (perMin >= 2) return CupertinoIcons.arrow_up;
    if (perMin >= 1) return CupertinoIcons.arrow_up_right;
    if (perMin > -1) return CupertinoIcons.arrow_right;
    if (perMin > -2) return CupertinoIcons.arrow_down_right;
    return CupertinoIcons.arrow_down;
  }

  Color _color(int v, ProfileGlucoseState s, GlucoseColors gc) {
    if (v < s.targetLow) return gc.low;
    if (v > s.targetHigh) return gc.high;
    return gc.inRange;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ProfileGlucoseState>();
    // The big headline uses its own per-theme palette (defined explicitly in
    // GlucoseColors): deeper on the light background, brighter on the dark one.
    final gc = Theme.of(context).brightness == Brightness.dark
        ? GlucoseColors.headlineDark
        : GlucoseColors.headlineLight;
    final v = mgdl;
    final color = v == null ? Colors.grey : _color(v, s, gc);
    final hasTrend = v != null && trendPerMin != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          v == null ? (busy ? '…' : '--') : s.format(v),
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
            // Nudge down so the arrow aligns with the top of the digits, not
            // the (taller) line box of the 90pt number.
            if (hasTrend) ...[
              Icon(_arrow(trendPerMin!), size: 52, color: color),
            ],
            if (hasTrend)
              Text(
                '${s.formatTrend(trendPerMin!)}/min',
                style: TextStyle(fontSize: 10, color: Colors.grey[400]),
              ),
            Text(
              s.unit.label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
