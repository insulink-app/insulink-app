import 'package:flutter/material.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_detail_page.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile.dart';
import 'package:insulink/src/sport/activity/sport_summary_tile.dart';

/// Builds the [SportSummaryTile] for a nutrition box from today's meals +
/// hydration. Shared by the nutrition stats grid and the overview's nutrition
/// boxes (mirrors the Sport tab's [TodayTileBuilder]). Tapping a box opens its
/// [NutritionDetailPage] (history + chart).
class NutritionTileBuilder {
  final MealState meals;
  final NutritionState hydration;

  NutritionTileBuilder(this.meals, this.hydration);

  SportSummaryTile build(BuildContext context, NutritionTile tile) {
    final labelKey = nutritionTileLabelKey(tile);
    final icon = nutritionTileIcon(tile);
    void openDetail() => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NutritionDetailPage(tile: tile),
          ),
        );
    switch (tile) {
      case NutritionTile.carbs:
        return SportSummaryTile(
          icon: icon,
          labelKey: labelKey,
          value: meals.todayCarbs.toStringAsFixed(0),
          unit: 'g',
          progress: _progress(meals.todayCarbs, hydration.carbsGoalG),
          onTap: openDetail,
        );
      case NutritionTile.protein:
        return SportSummaryTile(
          icon: icon,
          labelKey: labelKey,
          value: meals.todayProtein.toStringAsFixed(0),
          unit: 'g',
          progress: _progress(meals.todayProtein, hydration.proteinGoalG),
          onTap: openDetail,
        );
      case NutritionTile.bolus:
        return SportSummaryTile(
          icon: icon,
          labelKey: labelKey,
          value: meals.todayBolus.toStringAsFixed(1),
          unit: 'E',
          onTap: openDetail,
        );
      case NutritionTile.water:
        return SportSummaryTile(
          icon: icon,
          labelKey: labelKey,
          value: formatLitres(hydration.todayMl / 1000),
          unit: 'L',
          progress: hydration.todayFraction,
          onTap: openDetail,
        );
      case NutritionTile.meals:
        return SportSummaryTile(
          icon: icon,
          labelKey: labelKey,
          value: '${meals.todayCount}',
          onTap: openDetail,
        );
    }
  }

  double? _progress(double value, int goal) => goal <= 0 ? null : value / goal;
}
