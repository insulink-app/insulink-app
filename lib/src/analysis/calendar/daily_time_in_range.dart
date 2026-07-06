import 'dart:collection';

import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';

/// Per-day time-in-range over the long-term archive, for the calendar heatmap.
/// Buckets each reading into its LOCAL day and returns the fraction within the
/// user's target range (0..1) for every day that has data.
class DailyTimeInRange {
  DailyTimeInRange(this.archive, this.glucose);

  final SplayTreeMap<int, int> archive;
  final ProfileGlucoseState glucose;

  /// day (local midnight) → fraction of readings in target range.
  Map<DateTime, double> build() {
    final inRange = <DateTime, int>{};
    final total = <DateTime, int>{};
    archive.forEach((epochMin, mgdl) {
      final time = DateTime.fromMillisecondsSinceEpoch(epochMin * 60000);
      final day = DateTime(time.year, time.month, time.day);
      total[day] = (total[day] ?? 0) + 1;
      if (mgdl >= glucose.targetLow && mgdl <= glucose.targetHigh) {
        inRange[day] = (inRange[day] ?? 0) + 1;
      }
    });
    return {
      for (final day in total.keys) day: (inRange[day] ?? 0) / total[day]!,
    };
  }
}
