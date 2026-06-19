import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';

/// Big current-glucose readout with a Cupertino trend arrow, in a soft card
/// tinted by the glucose range. [stale] dims it while showing the last cached
/// reading before live data arrives.
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

    final unit = stale ? Locales.string(context, 'overview.cached') : 'mg/dL';
    final sub = trendPerMin != null
        ? '$unit · ${trendPerMin! >= 0 ? '+' : ''}'
              '${trendPerMin!.toStringAsFixed(1)}/min'
        : unit;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              v == null ? (busy ? '…' : '--') : '$v',
              style: TextStyle(
                fontSize: 80,
                fontWeight: FontWeight.bold,
                height: 1,
                color: color,
              ),
            ),
            if (v != null && trendPerMin != null) ...[
              const SizedBox(width: 10),
              Icon(_arrow(trendPerMin!), size: 56, color: color),
            ],
          ],
        ),
        if (v != null) ...[
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 13, color: Colors.grey[400])),
        ],
      ],
    );
  }
}
