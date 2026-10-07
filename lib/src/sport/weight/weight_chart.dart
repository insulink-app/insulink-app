import 'package:flutter/material.dart';
import 'package:insulink/src/base/measurement_chart.dart';
import 'package:insulink/src/sport/sport_models.dart';

/// Weight over time. A thin adapter over the shared [MeasurementChart] — the
/// weight-specific parts are only the unit and the goal line.
class WeightChart extends StatelessWidget {
  const WeightChart({
    super.key,
    required this.weights,
    this.goalKg,
    this.averageKg,
  });

  final List<WeightEntry> weights;

  /// Target weight drawn as a labelled horizontal line.
  final double? goalKg;

  /// Drawn as a dashed line.
  final double? averageKg;

  @override
  Widget build(BuildContext context) {
    return MeasurementChart(
      points: [
        for (final entry in weights)
          (atEpochMs: entry.atEpochMs, value: entry.kg),
      ],
      unit: 'kg',
      goal: goalKg,
      average: averageKg,
    );
  }
}
