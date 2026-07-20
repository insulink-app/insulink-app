import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training/training_metrics_chart.dart';
import 'package:provider/provider.dart';

/// The glucose + heart-rate chart over a workout's span — reused by the logbook
/// detail page and the end-of-workout summary. No GPS track for a strength
/// workout, so the hover callback is a no-op (the tooltip + haptics still work).
class WorkoutMetricsChart extends StatelessWidget {
  const WorkoutMetricsChart({super.key, required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final endMs = session.sets.isEmpty
        ? session.startedAtMs
        : session.sets.last.atEpochMs;
    // Pad the query so the chart can show the reading just before/after a short
    // workout too.
    const pad = Duration(minutes: 15);
    final glucose = context.watch<CgmController>().archiveBetween(
      DateTime.fromMillisecondsSinceEpoch(session.startedAtMs).subtract(pad),
      DateTime.fromMillisecondsSinceEpoch(endMs).add(pad),
    );
    return TrainingMetricsChart(
      startMs: session.startedAtMs,
      endMs: endMs,
      glucose: glucose,
      track: const [],
      onHoverMs: (_) {},
    );
  }
}
