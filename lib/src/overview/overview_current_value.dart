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

  /// The shared glucose colours are mid-tones tuned for the small profile cards;
  /// on the large 90pt headline they read too dark. Shift per theme: a brighter,
  /// MORE saturated tone on dark backgrounds, a deeper one on light backgrounds.
  /// Saturation is boosted too — raising lightness alone washes the colour out
  /// toward grey, which is exactly the "graucher" effect we want to avoid.
  Color _forHeadline(Color c, Brightness brightness) {
    final hsl = HSLColor.fromColor(c);
    if (brightness == Brightness.dark) {
      return hsl
          .withLightness((hsl.lightness + 0.18).clamp(0.0, 1.0))
          .withSaturation((hsl.saturation + 0.30).clamp(0.0, 1.0))
          .toColor();
    }
    return hsl
        .withLightness((hsl.lightness - 0.16).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + 0.20).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ProfileGlucoseState>();
    final gc = Theme.of(context).extension<GlucoseColors>()!;
    final v = mgdl;
    final color = v == null
        ? Colors.grey
        : _forHeadline(_color(v, s, gc), Theme.of(context).brightness);

    final sub = trendPerMin != null
        ? '${s.unit.label}  ·  ${s.formatTrend(trendPerMin!)}/min'
        : s.unit.label;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              v == null ? (busy ? '…' : '--') : s.format(v),
              style: TextStyle(
                fontSize: 90,
                fontWeight: FontWeight.bold,
                height: 1,
                color: color,
              ),
            ),
            if (v != null && trendPerMin != null) ...[
              const SizedBox(width: 10),
              Icon(_arrow(trendPerMin!), size: 64, color: color),
            ],
          ],
        ),
        Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
      ],
    );
  }
}
