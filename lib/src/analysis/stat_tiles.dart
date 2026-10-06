import 'package:flutter/material.dart';
import 'package:insulink/src/analysis/averages/glucose_summary.dart';
import 'package:insulink/src/base/metric_grid.dart';
import 'package:insulink/src/localization/locales.dart';

/// The analysis key figures in one [MetricGrid]: two per row, parted by thin
/// lines. Shared by the key-figure and the forecast view.
class AnalysisStatTiles extends StatelessWidget {
  const AnalysisStatTiles({super.key, required this.stats});

  final List<GlucoseStat> stats;

  @override
  Widget build(BuildContext context) {
    return MetricGrid(
      cells: [
        for (final stat in stats)
          (
            label: Locales.string(context, stat.labelKey),
            value: stat.value,
            unit: stat.unit.isEmpty ? null : stat.unit,
          ),
      ],
    );
  }
}
