import 'package:flutter/material.dart';

/// A configurable nutrition summary box.
enum NutritionTile { carbs, protein, bolus, water, meals }

/// Icon for a nutrition box (grid + layout editor).
IconData nutritionTileIcon(NutritionTile tile) => switch (tile) {
  NutritionTile.carbs => Icons.restaurant_rounded,
  NutritionTile.protein => Icons.egg_alt_rounded,
  NutritionTile.bolus => Icons.water_drop_rounded,
  NutritionTile.water => Icons.local_drink_rounded,
  NutritionTile.meals => Icons.restaurant_menu_rounded,
};

/// Localization key for a nutrition box label (grid + editor).
String nutritionTileLabelKey(NutritionTile tile) => switch (tile) {
  NutritionTile.carbs => 'nutrition.stats.carbs',
  NutritionTile.protein => 'nutrition.stats.protein',
  NutritionTile.bolus => 'nutrition.stats.bolus',
  NutritionTile.water => 'nutrition.hydration',
  NutritionTile.meals => 'nutrition.stats.meals',
};
