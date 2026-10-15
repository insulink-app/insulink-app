import 'package:flutter/material.dart';
import 'package:insulink/src/activity_mode/activity_mode_selector.dart';
import 'package:insulink/src/activity_mode/activity_mode_switch_state.dart';
import 'package:provider/provider.dart';

/// The hand choice on the overview, shown only when the user asked for it in
/// the profile and the activity mode is on at all. Renders nothing otherwise,
/// so the overview is unchanged for everyone else.
class ActivityModeOverviewSelector extends StatelessWidget {
  const ActivityModeOverviewSelector({super.key});

  @override
  Widget build(BuildContext context) {
    if (!context.watch<ActivityModeSwitchState>().showsOnOverview) {
      return const SizedBox.shrink();
    }
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 4, 4, 14),
      child: ActivityModeSelector(),
    );
  }
}
