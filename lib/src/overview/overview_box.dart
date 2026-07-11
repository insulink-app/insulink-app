import 'package:flutter/material.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile.dart';
import 'package:insulink/src/sport/activity/tile_layout_state.dart';
import 'package:insulink/src/sport/activity/today_tile_builder.dart';

/// Every box available on the overview grid: the Sport "Today" metrics followed
/// by the nutrition boxes, so both live in ONE personalizable section. Member
/// names match [TodayTile] / [NutritionTile] so a box maps back to its source by
/// name (and old stored layouts, keyed by those names, still parse).
enum OverviewBox {
  steps,
  distance,
  calories,
  weight,
  restingHr,
  sleep,
  heartRate,
  spo2,
  respiratoryRate,
  carbs,
  protein,
  bolus,
  water,
  meals,
}

extension OverviewBoxInfo on OverviewBox {
  /// Google Health boxes keep their slot but only render while connected.
  bool get isGoogleHealth =>
      index >= OverviewBox.restingHr.index &&
      index <= OverviewBox.respiratoryRate.index;

  /// The source Sport tile, or null when this is a nutrition box.
  TodayTile? get asTodayTile => TodayTile.values.asNameMap()[name];

  /// The source nutrition tile, or null when this is a Sport box.
  NutritionTile? get asNutritionTile => NutritionTile.values.asNameMap()[name];
}

IconData overviewBoxIcon(OverviewBox box) {
  final today = box.asTodayTile;
  return today != null
      ? todayTileIcon(today)
      : nutritionTileIcon(box.asNutritionTile!);
}

String overviewBoxLabelKey(OverviewBox box) {
  final today = box.asTodayTile;
  return today != null
      ? todayTileLabelKey(today)
      : nutritionTileLabelKey(box.asNutritionTile!);
}
