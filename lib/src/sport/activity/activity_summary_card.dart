import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/activity/activity_settings_sheet.dart';
import 'package:insulink/src/sport/activity/reorderable_tile_grid.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/activity/today_layout.dart';
import 'package:insulink/src/sport/activity/today_tile_builder.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// "Today" section: a grid of summary boxes the user can configure (which boxes
/// and their order — see [TodayLayoutState]) and reorder by dragging. Steps are
/// real; distance/calories are estimated; weight and the Google Health metrics come
/// from their states. Google Health boxes only appear while a Google Health is connected.
class ActivitySummaryCard extends StatelessWidget {
  const ActivitySummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<TodayLayoutState>();
    final activity = context.watch<SportActivityState>();
    final sport = context.watch<SportState>();
    final health = context.watch<GoogleHealthState>();
    final builder = TodayTileBuilder(activity, sport, health);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        const SizedBox(height: 12),
        ReorderableTileGrid(
          tiles: layout.visible(health.connected),
          state: layout,
          tileBuilder: builder.build,
        ),
        if (activity.permissionDenied) ...[
          const SizedBox(height: 10),
          LocaleText(
            'sport.activity.permission',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
          icon: const Icon(PhosphorIconsBold.slidersHorizontal, size: 20),
          onPressed: () => showActivitySettingsSheet(context),
        ),
      ],
    );
  }
}
