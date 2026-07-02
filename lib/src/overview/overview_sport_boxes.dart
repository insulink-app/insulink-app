import 'package:flutter/material.dart';
import 'package:insulink/src/sport/activity/activity_detail_page.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/activity/sport_summary_tile.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:insulink/src/sport/weight/weight_detail_page.dart';
import 'package:provider/provider.dart';

/// Two sport summary boxes on the overview: today's steps and latest weight,
/// each tapping through to its detail page. Reuses the Sport tab's tile + state.
class OverviewSportBoxes extends StatelessWidget {
  const OverviewSportBoxes({super.key});

  @override
  Widget build(BuildContext context) {
    final activity = context.watch<SportActivityState>();
    final latestWeight = context.watch<SportState>().latestWeight;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SportSummaryTile(
              icon: Icons.directions_walk,
              labelKey: 'sport.activity.steps',
              value: sportInt(activity.todaySteps),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const ActivityDetailPage(metric: ActivityMetric.steps),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SportSummaryTile(
              icon: Icons.monitor_weight,
              labelKey: 'sport.weight',
              value: latestWeight == null
                  ? '–'
                  : sportDecimal(latestWeight.kg, 1),
              unit: latestWeight == null ? null : 'kg',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const WeightDetailPage()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
