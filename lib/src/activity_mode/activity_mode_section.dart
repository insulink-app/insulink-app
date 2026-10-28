import 'package:flutter/material.dart';
import 'package:insulink/src/activity_mode/activity_mode_selector.dart';
import 'package:insulink/src/activity_mode/activity_mode_settings.dart';
import 'package:insulink/src/activity_mode/activity_mode_switch_state.dart';
import 'package:insulink/src/base/info_button.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/profile/notifications/notification_threshold.dart';
import 'package:insulink/src/profile/notifications/notification_threshold_card.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:provider/provider.dart';

/// One heading of the activity section and the numbers under it.
typedef ActivityModeGroup = ({
  String titleKey,
  String infoKey,
  List<NotificationThreshold> settings,
});

/// The profile's activity section: the switch, whether the choice also sits on
/// the overview and the mode chosen by hand, then the numbers grouped by what
/// they belong to, each group with its explanation behind an ⓘ.
///
/// The overview switch and the hand choice only show while the mode is on,
/// since with it off both would be ignored. The numbers always show, so they
/// can be set before the mode is switched on.
class ActivityModeSection extends StatelessWidget {
  const ActivityModeSection({super.key});

  /// Grouped by when a number applies: while moving, while lifting, in the
  /// hours after, and in the calculator during those hours. The labels inside
  /// a group are short because the heading already says which mode they are
  /// for.
  static const List<ActivityModeGroup> groups = [
    (
      titleKey: 'profile.activity_mode.group.endurance',
      infoKey: 'profile.activity_mode.group.endurance_info',
      settings: [
        ActivityModeSettings.enduranceTarget,
        ActivityModeSettings.enduranceBasal,
        ActivityModeSettings.pulseThreshold,
      ],
    ),
    (
      titleKey: 'profile.activity_mode.group.strength',
      infoKey: 'profile.activity_mode.group.strength_info',
      settings: [ActivityModeSettings.strengthBasal],
    ),
    (
      titleKey: 'profile.activity_mode.group.recovery',
      infoKey: 'profile.activity_mode.group.recovery_info',
      settings: [
        ActivityModeSettings.recoveryHours,
        ActivityModeSettings.recoveryTarget,
        ActivityModeSettings.recoveryBasal,
      ],
    ),
    (
      titleKey: 'profile.activity_mode.group.recovery_bolus',
      infoKey: 'profile.activity_mode.group.recovery_bolus_info',
      settings: [
        ActivityModeSettings.recoveryBolusMinutes,
        ActivityModeSettings.recoveryBolus,
      ],
    ),
  ];

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
        for (final group in groups) ..._group(group),
      ],
    );
  }

  List<Widget> _group(ActivityModeGroup group) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SectionHeader(
          titleKey: group.titleKey,
          topGap: InkSpace.sectionGap,
          actions: [
            InfoButton(titleKey: group.titleKey, bodyKey: group.infoKey),
          ],
        ),
      ),
      for (final setting in group.settings) ...[
        NotificationThresholdCard(setting),
        if (setting != group.settings.last) const SizedBox(height: 10),
      ],
    ];
  }
}
