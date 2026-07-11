import 'package:flutter/material.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile_builder.dart';
import 'package:insulink/src/overview/overview_box.dart';
import 'package:insulink/src/sport/activity/sport_summary_tile.dart';
import 'package:insulink/src/sport/activity/today_tile_builder.dart';

/// Builds the [SportSummaryTile] for an [OverviewBox], delegating to the Sport or
/// nutrition tile builder depending on the box's source.
class OverviewBoxBuilder {
  final TodayTileBuilder today;
  final NutritionTileBuilder nutrition;

  OverviewBoxBuilder(this.today, this.nutrition);

  SportSummaryTile build(BuildContext context, OverviewBox box) {
    final todayTile = box.asTodayTile;
    return todayTile != null
        ? today.build(context, todayTile)
        : nutrition.build(context, box.asNutritionTile!);
  }
}
