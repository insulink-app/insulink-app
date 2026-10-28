import 'package:flutter/material.dart';
import 'package:insulink/src/activity_mode/activity_mode_selector.dart';
import 'package:insulink/src/activity_mode/activity_mode_settings.dart';
import 'package:insulink/src/activity_mode/activity_mode_switch_state.dart';
import 'package:insulink/src/profile/notifications/notification_threshold_card.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';
import 'package:provider/provider.dart';

/// The profile's activity section: the switch, whether the choice also sits on
/// the overview, the mode chosen by hand, and the numbers each mode applies.
///
/// The overview switch and the hand choice only show while the mode is on,
/// since with it off both would be ignored. The numbers always show, so they
/// can be set before the mode is switched on.
class ActivityModeSection extends StatelessWidget {
  const ActivityModeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final switches = context.watch<ActivityModeSwitchState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileToggleRow(
          labelKey: ActivityModeSettings.enabled.labelKey,
          value: switches.enabled,
          onChanged: switches.setEnabled,
        ),
        if (switches.enabled) ...[
          const SizedBox(height: 4),
          ProfileToggleRow(
            labelKey: ActivityModeSettings.onOverview.labelKey,
            value: switches.onOverview,
            onChanged: switches.setOnOverview,
          ),
          const SizedBox(height: 12),
          const ActivityModeSelector(),
        ],
        for (final setting in ActivityModeSettings.all) ...[
          const SizedBox(height: 10),
          NotificationThresholdCard(setting),
        ],
      ],
    );
  }
}
