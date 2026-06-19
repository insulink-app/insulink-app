import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';

/// Big current-glucose readout with a trend arrow. [stale] dims the value when
/// it's the last cached reading shown before live data arrives.
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

  String _arrow(double perMin) {
    if (perMin >= 3) return '⇈';
    if (perMin >= 2) return '↑';
    if (perMin >= 1) return '↗';
    if (perMin > -1) return '→';
    if (perMin > -2) return '↘';
    if (perMin > -3) return '↓';
    return '⇊';
  }

  Color _color(int v) {
    if (v < 70) return Colors.redAccent;
    if (v > 180) return Colors.orangeAccent;
    return Colors.tealAccent;
  }

  @override
  Widget build(BuildContext context) {
    final v = mgdl;
    if (v == null) {
      return Text(
        busy ? '…' : '--',
        style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold),
      );
    }
    final color = stale ? _color(v).withValues(alpha: 0.5) : _color(v);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$v',
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        if (trendPerMin != null)
          Text(
            _arrow(trendPerMin!),
            style: TextStyle(fontSize: 40, color: color),
          ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              stale ? Locales.string(context, 'overview.cached') : 'mg/dL',
              style: TextStyle(color: Colors.grey[400]),
            ),
            if (trendPerMin != null)
              Text(
                '${trendPerMin! >= 0 ? '+' : ''}'
                '${trendPerMin!.toStringAsFixed(1)}/min',
                style: TextStyle(color: Colors.grey[400]),
              ),
          ],
        ),
      ],
    );
  }
}
