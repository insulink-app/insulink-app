import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_layout_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_settings_sheet.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile_builder.dart';
import 'package:insulink/src/sport/activity/reorderable_tile_grid.dart';
import 'package:provider/provider.dart';

/// Top of the nutrition page: today's summary boxes (carbs / protein / bolus /
/// water / meals), mirroring the Sport tab's "Today" grid — drag to reorder,
/// toggle on/off in the settings sheet. Carbs, protein and water show goal
/// progress; the settings button opens the unified goal + layout editor.
class NutritionStatsSection extends StatelessWidget {
  const NutritionStatsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<NutritionLayoutState>();
    final builder = NutritionTileBuilder(
      context.watch<MealState>(),
      context.watch<NutritionState>(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        const SizedBox(height: 12),
        ReorderableTileGrid<NutritionTile>(
          tiles: layout.visible(true),
          state: layout,
          tileBuilder: builder.build,
        ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        LocaleText(
          'nutrition.today',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.tune, size: 20),
          onPressed: () => showNutritionSettingsSheet(context),
        ),
      ],
    );
  }
}
