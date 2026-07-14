import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// A configurable nutrition summary box.
enum NutritionTile { carbs, protein, bolus, water, meals }

/// Icon for a nutrition box (grid + layout editor).
IconData nutritionTileIcon(NutritionTile tile) => switch (tile) {
  NutritionTile.carbs => PhosphorIconsRegular.grains,
  NutritionTile.protein => PhosphorIconsRegular.egg,
  NutritionTile.bolus => PhosphorIconsRegular.syringe,
  NutritionTile.water => PhosphorIconsRegular.drop,
  NutritionTile.meals => PhosphorIconsRegular.forkKnife,
};

/// Localization key for a nutrition box label (grid + editor).
String nutritionTileLabelKey(NutritionTile tile) => switch (tile) {
  NutritionTile.carbs => 'nutrition.stats.carbs',
  NutritionTile.protein => 'nutrition.stats.protein',
  NutritionTile.bolus => 'nutrition.stats.bolus',
  NutritionTile.water => 'nutrition.hydration',
  NutritionTile.meals => 'nutrition.stats.meals',
};
