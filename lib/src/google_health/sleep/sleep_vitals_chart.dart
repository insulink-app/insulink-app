import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/sport/training/training_metrics_chart.dart';
import 'package:provider/provider.dart';

/// Glucose and heart rate across one night, drawn by the same chart a training
/// uses. A night has no route, so there is no speed line and the hover has
/// nothing to point at.
class SleepVitalsChart extends StatelessWidget {
  const SleepVitalsChart({super.key, required this.timeline});

  /// The night's sleep session; the chart spans its first to its last segment.
  final List<SleepSegment> timeline;

  /// Glucose is read 15 minutes past either edge, so the line enters and leaves
  /// the night with context, as on a training.
  @override
  Widget build(BuildContext context) {
    final startMs = timeline.first.startMs;
    final endMs = timeline.last.endMs;
    const pad = Duration(minutes: 15);
    final glucose = context.watch<CgmController>().archiveBetween(
      DateTime.fromMillisecondsSinceEpoch(startMs).subtract(pad),
      DateTime.fromMillisecondsSinceEpoch(endMs).add(pad),
    );
    return TrainingMetricsChart(
      key: ValueKey(startMs),
      startMs: startMs,
      endMs: endMs,
      glucose: glucose,
      track: const [],
      onHoverMs: (_) {},
      emptyKey: 'google_health.sleep_page.no_vitals',
    );
  }
}
