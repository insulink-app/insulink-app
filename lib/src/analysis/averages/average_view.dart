import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/analysis/averages/glucose_summary.dart';
import 'package:insulink/src/analysis/stat_tiles.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Summary glucose statistics over the cached history: average, GMI (estimated
/// HbA1c), variability (CV), standard deviation and the extremes.
class AverageView extends StatelessWidget {
  const AverageView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final glucose = context.watch<ProfileGlucoseState>();

    // Long-term archive (spans sensor swaps), not the current-session cache.
    final values = controller.statsArchive.values.toList();
    if (values.isEmpty) {
      return const EmptyState(
        icon: PhosphorIconsBold.chartLineUp,
        titleKey: 'analysis.empty',
      );
    }
    final stats = GlucoseSummary(values, glucose).build();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AnalysisStatTiles(stats: stats),
        ),
      ),
    );
  }
}
