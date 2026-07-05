import 'package:flutter/material.dart';
import 'package:insulink/src/fitbit/fitbit_state.dart';
import 'package:insulink/src/overview/overview_layout.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/sport/activity/reorderable_tile_grid.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/activity/tile_layout_editor.dart';
import 'package:insulink/src/sport/activity/today_tile_builder.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';

/// Personalizable summary boxes on the overview: the user picks which boxes and
/// their order (drag to reorder, tune icon to show/hide). Defaults to steps +
/// weight. Reuses the Sport tab's tile builder, grid and editor.
class OverviewSportBoxes extends StatelessWidget {
  const OverviewSportBoxes({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<OverviewLayoutState>();
    final activity = context.watch<SportActivityState>();
    final sport = context.watch<SportState>();
    final fitbit = context.watch<FitbitState>();
    final builder = TodayTileBuilder(activity, sport, fitbit);
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
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            onPressed: () => _edit(context, layout),
          ),
        ),
        const SizedBox(height: 4),
        ReorderableTileGrid(
          tiles: layout.visible(fitbit.connected),
          state: layout,
          tileBuilder: builder.build,
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, OverviewLayoutState layout) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TileLayoutEditor(
          state: layout,
          titleKey: 'sport.layout.title',
          hintKey: 'sport.layout.hint',
        ),
      ),
    );
    if (context.mounted) {
      await ProfileSettings().push(context);
    }
  }
}
