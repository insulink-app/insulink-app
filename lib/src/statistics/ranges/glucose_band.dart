import 'package:flutter/material.dart';

import '../../profile/glucose/profile_glucose_state.dart';
import '../../theme/glucose_colors.dart';

/// One glucose band in the time-in-range breakdown (a single segment of the
/// stacked bar + its legend row).
class GlucoseBand {
  const GlucoseBand({
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

/// Builds the time-in-range bands (top → bottom: very high … very low, matching
/// Dexcom's ordering) from the archived glucose [values], using the user's
/// thresholds and the themed band colours.
class TimeInRangeBands {
  TimeInRangeBands({
    required this.values,
    required this.glucose,
    required this.colors,
  });

  final Iterable<int> values;
  final ProfileGlucoseState glucose;
  final GlucoseColors colors;

  List<GlucoseBand> build() {
    final counts = _counts();
    final total = counts.fold<int>(0, (sum, count) => sum + count);
    if (total == 0) {
      return const [];
    }
    final fractions = [for (final count in counts) count / total];
    final percents = _largestRemainderPercents(fractions);
    return [
      _band(
        'very_high',
        _darken(colors.high),
        fractions,
        percents,
        counts,
        0,
        '> ${glucose.format(glucose.urgentHigh)}',
      ),
      _band(
        'high',
        colors.high,
        fractions,
        percents,
        counts,
        1,
        '${glucose.format(glucose.targetHigh)}–${glucose.format(glucose.urgentHigh)}',
      ),
      _band(
        'in_range',
        colors.inRange,
        fractions,
        percents,
        counts,
        2,
        '${glucose.format(glucose.targetLow)}–${glucose.format(glucose.targetHigh)}',
      ),
      _band(
        'low',
        colors.low,
        fractions,
        percents,
        counts,
        3,
        '${glucose.format(glucose.urgentLow)}–${glucose.format(glucose.targetLow)}',
      ),
      _band(
        'very_low',
        _darken(colors.low),
        fractions,
        percents,
        counts,
        4,
        '< ${glucose.format(glucose.urgentLow)}',
      ),
    ];
  }

  /// Readings per zone, top → bottom: very high, high, in range, low, very low.
  /// Counts are a faithful time proxy since readings arrive ~every 5 min.
  List<int> _counts() {
    var veryLow = 0, low = 0, inRange = 0, high = 0, veryHigh = 0;
    for (final value in values) {
      if (value < glucose.urgentLow) {
        veryLow++;
      } else if (value < glucose.targetLow) {
        low++;
      } else if (value <= glucose.targetHigh) {
        inRange++;
      } else if (value <= glucose.urgentHigh) {
        high++;
      } else {
        veryHigh++;
      }
    }
    return [veryHigh, high, inRange, low, veryLow];
  }

  GlucoseBand _band(
    String slug,
    Color color,
    List<double> fractions,
    List<int> percents,
    List<int> counts,
    int index,
    String rangeLabel,
  ) {
    return GlucoseBand(
      labelKey: 'statistics.range.$slug',
      color: color,
      fraction: fractions[index],
      rangeLabel: rangeLabel,
      pctLabel: _pctLabel(counts[index], percents[index]),
    );
  }

  String _pctLabel(int count, int percent) {
    if (count == 0) {
      return '0%';
    }
    if (percent == 0) {
      return '<1%';
    }
    return '$percent%';
  }

  /// The two "very" bands reuse the low/high hues, darkened for separation.
  Color _darken(Color color) => Color.lerp(color, Colors.black, 0.28)!;

  /// Integer percentages that sum to exactly 100, via the largest-remainder
  /// method — so the displayed numbers don't add up to 99 or 101 after rounding.
  List<int> _largestRemainderPercents(List<double> fractions) {
    final raw = [for (final fraction in fractions) fraction * 100];
    final result = [for (final value in raw) value.floor()];
    var remaining = 100 - result.fold<int>(0, (sum, value) => sum + value);
    final order = List<int>.generate(raw.length, (index) => index)
      ..sort(
        (left, right) =>
            (raw[right] - result[right]).compareTo(raw[left] - result[left]),
      );
    for (var index = 0; index < order.length && remaining > 0; index++) {
      result[order[index]]++;
      remaining--;
    }
    return result;
  }
}
