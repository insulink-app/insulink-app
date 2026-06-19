import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Compact current-glucose readout with a Cupertino trend arrow. [stale] dims it
/// while showing the last cached reading before live data arrives.
class OverviewCurrentValue extends StatelessWidget {
  const OverviewCurrentValue({
    super.key,
    required this.mgdl,
    required this.trendPerMin,
    required this.stale,
    required this.busy,
  });

  final int? mgdl;
  final double? trendPerMin;
  final bool stale;
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

  Color _color(int v) {
    if (v < 70) return Colors.redAccent;
    if (v > 180) return Colors.orangeAccent;
    return Colors.tealAccent;
  }

  @override
  Widget build(BuildContext context) {
    final v = mgdl;
    final base = v == null ? Colors.grey : _color(v);
    final color = stale ? base.withValues(alpha: 0.5) : base;

    final sub = trendPerMin != null
        ? 'mg/dL  ·  ${trendPerMin! >= 0 ? '+' : ''}'
              '${trendPerMin!.toStringAsFixed(1)}/min'
        : 'mg/dL';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              v == null ? (busy ? '…' : '--') : '$v',
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
