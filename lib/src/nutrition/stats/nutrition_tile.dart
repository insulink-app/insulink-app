import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// A configurable nutrition summary box.
enum NutritionTile { carbs, protein, bolus, water, meals }

/// Icon for a nutrition box (grid + layout editor).
///
/// Bold weight, unlike the rest of the app: a summary box carries its glyph
/// bare, with no badge behind it, so the thin Regular stroke washes out against
/// the box's tint. The heavier stroke gives it presence without a louder colour.
IconData nutritionTileIcon(NutritionTile tile) => switch (tile) {
  NutritionTile.carbs => PhosphorIconsBold.grains,
  NutritionTile.protein => PhosphorIconsBold.egg,
  NutritionTile.bolus => PhosphorIconsBold.syringe,
  NutritionTile.water => PhosphorIconsBold.drop,
  NutritionTile.meals => PhosphorIconsBold.forkKnife,
};

/// Localization key for a nutrition box label (grid + editor).
String nutritionTileLabelKey(NutritionTile tile) => switch (tile) {
  NutritionTile.carbs => 'nutrition.stats.carbs',
  NutritionTile.protein => 'nutrition.stats.protein',
  NutritionTile.bolus => 'nutrition.stats.bolus',
  NutritionTile.water => 'nutrition.hydration',
  NutritionTile.meals => 'nutrition.stats.meals',
};
