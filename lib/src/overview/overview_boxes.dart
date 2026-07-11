import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile_builder.dart';
import 'package:insulink/src/overview/overview_box.dart';
import 'package:insulink/src/overview/overview_box_builder.dart';
import 'package:insulink/src/overview/overview_layout.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/sport/activity/reorderable_tile_grid.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/activity/tile_layout_editor.dart';
import 'package:insulink/src/sport/activity/today_tile_builder.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';

/// Personalizable summary boxes on the overview: Sport metrics AND nutrition
/// boxes in ONE section with a single settings button. The user picks which
/// boxes and their order (drag to reorder, tune icon to show/hide). Reuses the
/// shared grid + editor and both tile builders.
class OverviewBoxes extends StatelessWidget {
  const OverviewBoxes({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<OverviewLayoutState>();
    final health = context.watch<GoogleHealthState>();
    final builder = OverviewBoxBuilder(
      TodayTileBuilder(
        context.watch<SportActivityState>(),
        context.watch<SportState>(),
        health,
      ),
      NutritionTileBuilder(
        context.watch<MealState>(),
        context.watch<NutritionState>(),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.tune,
              size: 20,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            onPressed: () => _edit(context, layout),
          ),
        ),
        const SizedBox(height: 4),
        ReorderableTileGrid<OverviewBox>(
          tiles: layout.visible(health.connected),
          state: layout,
          tileBuilder: builder.build,
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, OverviewLayoutState layout) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TileLayoutEditor<OverviewBox>(
          state: layout,
          titleKey: 'sport.layout.title',
          hintKey: 'sport.layout.hint',
          icon: overviewBoxIcon,
          labelKey: overviewBoxLabelKey,
        ),
      ),
    );
    if (context.mounted) {
      await ProfileSettings().push(context);
    }
  }
}
