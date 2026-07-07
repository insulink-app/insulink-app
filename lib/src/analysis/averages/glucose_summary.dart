import 'dart:math' as math;

import '../../profile/glucose/profile_glucose_state.dart';

/// One computed summary statistic, formatted for display as a tile.
class GlucoseStat {
  const GlucoseStat(this.labelKey, this.value, this.unit);
  final String labelKey;
  final String value;
  final String unit;
}

/// Computes the summary glucose statistics (average, GMI, CV, SD, extremes)
/// over a set of mg/dL [values], formatted in the user's display unit. UI-free
/// so the maths stays testable.
class GlucoseSummary {
  GlucoseSummary(this.values, this.glucose);

  final List<int> values;
  final ProfileGlucoseState glucose;

  /// The six stat tiles in display order. [values] must not be empty.
  List<GlucoseStat> build() {
    final mean = values.reduce((sum, value) => sum + value) / values.length;
    final sd = math.sqrt(_variance(mean));
    final unit = glucose.unit.label;
    return [
      GlucoseStat('analysis.avg.mean', glucose.format(mean.round()), unit),
      GlucoseStat('analysis.avg.gmi', _gmi(mean).toStringAsFixed(1), '%'),
      GlucoseStat('analysis.avg.cv', _cv(mean, sd).toStringAsFixed(1), '%'),
      GlucoseStat('analysis.avg.sd', glucose.format(sd.round()), unit),
      GlucoseStat(
        'analysis.avg.max',
        glucose.format(values.reduce(math.max)),
        unit,
      ),
      GlucoseStat(
        'analysis.avg.min',
        glucose.format(values.reduce(math.min)),
        unit,
      ),
    ];
  }

  double _variance(double mean) =>
      values.fold<double>(0, (sum, value) => sum + math.pow(value - mean, 2)) /
      values.length;

  double _cv(double mean, double sd) => mean == 0 ? 0.0 : sd / mean * 100;

  /// Standard CGM GMI formula (estimated A1c) — always a percentage.
  double _gmi(double mean) => 3.31 + 0.02392 * mean;
}
