import 'package:flutter/material.dart';
import 'package:insulink/src/fitbit/fitbit_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/activity/activity_settings_sheet.dart';
import 'package:insulink/src/sport/activity/reorderable_tile_grid.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/activity/today_layout.dart';
import 'package:insulink/src/sport/activity/today_tile_builder.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';

/// "Today" section: a grid of summary boxes the user can configure (which boxes
/// and their order — see [TodayLayoutState]) and reorder by dragging. Steps are
/// real; distance/calories are estimated; weight and the Fitbit metrics come
/// from their states. Fitbit boxes only appear while a Fitbit is connected.
class ActivitySummaryCard extends StatelessWidget {
  const ActivitySummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<TodayLayoutState>();
    final activity = context.watch<SportActivityState>();
    final sport = context.watch<SportState>();
    final fitbit = context.watch<FitbitState>();
    final builder = TodayTileBuilder(activity, sport, fitbit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        const SizedBox(height: 12),
        ReorderableTileGrid(
          tiles: layout.visible(fitbit.connected),
          state: layout,
          tileBuilder: builder.build,
        ),
        if (activity.permissionDenied) ...[
          const SizedBox(height: 10),
          LocaleText(
            'sport.activity.permission',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        LocaleText(
          'sport.today',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.tune, size: 20),
          onPressed: () => showActivitySettingsSheet(context),
        ),
      ],
    );
  }
}
