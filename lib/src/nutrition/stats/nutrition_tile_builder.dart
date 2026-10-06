import 'package:flutter/material.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_detail_page.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile.dart';
import 'package:insulink/src/base/stat_tile.dart';
import 'package:insulink/src/sport/sport_format.dart';

/// Builds the [StatTile] for a nutrition box from today's meals +
/// hydration. Shared by the nutrition stats grid and the overview's nutrition
/// boxes (mirrors the Sport tab's [TodayTileBuilder]). Tapping a box opens its
/// [NutritionDetailPage] (history + chart).
class NutritionTileBuilder {
  final MealState meals;
  final NutritionState hydration;

  NutritionTileBuilder(this.meals, this.hydration);

  StatTile build(BuildContext context, NutritionTile tile) {
    final labelKey = nutritionTileLabelKey(tile);
    final icon = nutritionTileIcon(tile);
    void openDetail() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NutritionDetailPage(tile: tile)),
    );
    switch (tile) {
      case NutritionTile.carbs:
        return StatTile(
          icon: icon,
          labelKey: labelKey,
          value: sportDecimal(meals.todayCarbs, 0),
          unit: 'g',
          progress: _progress(meals.todayCarbs, hydration.carbsGoalG),
          onTap: openDetail,
        );
      case NutritionTile.protein:
        return StatTile(
          icon: icon,
          labelKey: labelKey,
          value: sportDecimal(meals.todayProtein, 0),
          unit: 'g',
          progress: _progress(meals.todayProtein, hydration.proteinGoalG),
          onTap: openDetail,
        );
      case NutritionTile.bolus:
        return StatTile(
          icon: icon,
          labelKey: labelKey,
          value: sportDecimal(meals.todayBolus, 1),
          unit: 'E',
          onTap: openDetail,
        );
      case NutritionTile.water:
        return StatTile(
          icon: icon,
          labelKey: labelKey,
          value: formatLitres(hydration.todayMl / 1000),
          unit: 'L',
          progress: hydration.todayFraction,
          onTap: openDetail,
        );
      case NutritionTile.meals:
        return StatTile(
          icon: icon,
          labelKey: labelKey,
          value: '${meals.todayCount}',
          onTap: openDetail,
        );
    }
  }

  double? _progress(double value, int goal) => goal <= 0 ? null : value / goal;
}
