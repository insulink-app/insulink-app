import 'package:flutter/material.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// One glucose band in the time-in-range breakdown (a single segment of the
/// stacked bar + its legend row).
class _Band {
  const _Band({
    required this.labelKey,
    required this.color,
    required this.fraction,
    required this.rangeLabel,
    required this.pctLabel,
  });

  /// Localization key for the band name (e.g. "Im Zielbereich").
  final String labelKey;
  final Color color;

  /// Share of readings in this band, 0..1 (drives the bar segment height).
  final double fraction;

  /// Human-readable bound description in the display unit (e.g. "70–180").
  final String rangeLabel;

  /// Pre-formatted percentage text: "0%" only when truly empty, "<1%" for a
  /// non-empty band that rounds to zero, else the integer percent.
  final String pctLabel;
}

/// Integer percentages that sum to exactly 100, via the largest-remainder
/// method — so the displayed numbers don't add up to 99 or 101 after rounding.
List<int> _largestRemainderPercents(List<double> fractions) {
  final raw = [for (final f in fractions) f * 100];
  final result = [for (final r in raw) r.floor()];
  var remaining = 100 - result.fold<int>(0, (a, b) => a + b);
  // Hand the leftover points to the bands with the largest fractional parts.
  final order = List<int>.generate(raw.length, (i) => i)
    ..sort((a, b) => (raw[b] - result[b]).compareTo(raw[a] - result[a]));
  for (var i = 0; i < order.length && remaining > 0; i++, remaining--) {
    result[order[i]]++;
  }
  return result;
}

/// Dexcom-style "time in ranges": a single vertical stacked bar whose segments
/// are sized by the share of readings in each glucose band, with the band name,
/// its bounds and the percentage listed to the right.
class TimeInRangeView extends StatelessWidget {
  const TimeInRangeView({super.key});

  @override
  Widget build(BuildContext context) {
    final g7 = context.watch<G7Controller>();
    final s = context.watch<ProfileGlucoseState>();
    final gc = Theme.of(context).extension<GlucoseColors>()!;

    // Long-term archive (spans sensor swaps), not the current-session cache.
    final values = g7.archiveSince(G7Controller.statsWindow).values;
    if (values.isEmpty) {
      return Center(child: LocaleText('statistics.empty'));
    }

    // Count readings per zone. Readings arrive ~every 5 min, so a count-based
    // share is a faithful approximation of time spent in each band.
    var veryLow = 0, low = 0, inRange = 0, high = 0, veryHigh = 0;
    for (final v in values) {
      if (v < s.urgentLow) {
        veryLow++;
      } else if (v < s.targetLow) {
        low++;
      } else if (v <= s.targetHigh) {
        inRange++;
      } else if (v <= s.urgentHigh) {
        high++;
      } else {
        veryHigh++;
      }
    }
    final total = values.length;

    // The two "very" bands reuse the low/high hues, darkened for separation.
    Color darken(Color c) => Color.lerp(c, Colors.black, 0.28)!;

    // Top → bottom, matching Dexcom's ordering (very high at the top).
    final counts = [veryHigh, high, inRange, low, veryLow];
    final fractions = [for (final c in counts) c / total];
    final percents = _largestRemainderPercents(fractions);
    String pctLabel(int i) {
      if (counts[i] == 0) {
        return '0%';
      }
      if (percents[i] == 0) {
        return '<1%';
      }
      return '${percents[i]}%';
    }

    final bands = <_Band>[
      _Band(
        labelKey: 'statistics.range.very_high',
        color: darken(gc.high),
        fraction: fractions[0],
        rangeLabel: '> ${s.format(s.urgentHigh)}',
        pctLabel: pctLabel(0),
      ),
      _Band(
        labelKey: 'statistics.range.high',
        color: gc.high,
        fraction: fractions[1],
        rangeLabel: '${s.format(s.targetHigh)}–${s.format(s.urgentHigh)}',
        pctLabel: pctLabel(1),
      ),
      _Band(
        labelKey: 'statistics.range.in_range',
        color: gc.inRange,
        fraction: fractions[2],
        rangeLabel: '${s.format(s.targetLow)}–${s.format(s.targetHigh)}',
        pctLabel: pctLabel(2),
      ),
      _Band(
        labelKey: 'statistics.range.low',
        color: gc.low,
        fraction: fractions[3],
        rangeLabel: '${s.format(s.urgentLow)}–${s.format(s.targetLow)}',
        pctLabel: pctLabel(3),
      ),
      _Band(
        labelKey: 'statistics.range.very_low',
        color: darken(gc.low),
        fraction: fractions[4],
        rangeLabel: '< ${s.format(s.urgentLow)}',
        pctLabel: pctLabel(4),
      ),
    ];

    // Sits near the top (not stretched over the whole page) and is centred
    // horizontally with a comfortable max width on wider screens.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SizedBox(
            height: 260,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StackedBar(bands: bands),
                const SizedBox(width: 24),
                Expanded(
                  child: _Legend(bands: bands, unitLabel: s.unit.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The single stacked bar — one coloured segment per band, sized by share.
class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.bands});

  final List<_Band> bands;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            for (final b in bands)
              if (b.fraction > 0)
                Expanded(
                  // Per-mille flex keeps the proportions; clamp to 1 so a tiny
                  // but non-zero band stays visible as a sliver.
                  flex: (b.fraction * 1000).round().clamp(1, 1000),
                  child: Container(color: b.color),
                ),
          ],
        ),
      ),
    );
  }
}

/// The right-hand legend: band name + bounds + percentage, one row per band,
/// spread over the full height so each roughly tracks its bar segment.
class _Legend extends StatelessWidget {
  const _Legend({required this.bands, required this.unitLabel});

  final List<_Band> bands;
  final String unitLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in bands)
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: b.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LocaleText(
                      b.labelKey,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${b.rangeLabel} $unitLabel',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                b.pctLabel,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
