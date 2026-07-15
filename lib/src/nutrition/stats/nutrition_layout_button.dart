import 'package:flutter/material.dart';
import 'package:insulink/src/nutrition/stats/nutrition_layout_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile.dart';
import 'package:insulink/src/sport/activity/tile_layout_button.dart';
import 'package:provider/provider.dart';

/// Opens the nutrition stats box editor from the nutrition settings sheet.
class NutritionLayoutButton extends StatelessWidget {
  const NutritionLayoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TileLayoutButton<NutritionTile>(
      state: context.read<NutritionLayoutState>(),
      icon: nutritionTileIcon,
      labelKey: nutritionTileLabelKey,
    );
  }
}
