import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/hba1c/hba1c_state.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile_builder.dart';
import 'package:insulink/src/overview/overview_box.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/activity/sport_summary_tile.dart';
import 'package:insulink/src/sport/activity/today_tile_builder.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';

/// Builds the [SportSummaryTile] for an [OverviewBox], delegating to the Sport or
/// nutrition tile builder depending on the box's source — a box maps to its
/// source by NAME, so there is no per-box wiring here at all.
class OverviewBoxBuilder {
  final TodayTileBuilder today;
  final NutritionTileBuilder nutrition;

  OverviewBoxBuilder(this.today, this.nutrition);

  /// Builder wired to the current provider tree. Every screen that renders
  /// overview boxes needs the same sources, so they are gathered once here
  /// rather than re-listed at each call site.
  factory OverviewBoxBuilder.of(BuildContext context) => OverviewBoxBuilder(
    TodayTileBuilder(
      context.watch<SportActivityState>(),
      context.watch<SportState>(),
      context.watch<GoogleHealthState>(),
      context.watch<Hba1cState>(),
    ),
    NutritionTileBuilder(
      context.watch<MealState>(),
      context.watch<NutritionState>(),
    ),
  );

  SportSummaryTile build(BuildContext context, OverviewBox box) {
    final todayTile = box.asTodayTile;
    return todayTile != null
        ? today.build(context, todayTile)
        : nutrition.build(context, box.asNutritionTile!);
  }
}
