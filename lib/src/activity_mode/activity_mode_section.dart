import 'package:flutter/material.dart';
import 'package:insulink/src/activity_mode/activity_mode_selector.dart';
import 'package:insulink/src/activity_mode/activity_mode_settings.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/profile/notifications/notification_threshold_card.dart';
import 'package:insulink/src/profile/notifications/notification_toggle.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';

/// The profile's activity section: the switch, the mode chosen by hand, and
/// the numbers each mode applies.
///
/// The hand choice only shows while the mode is switched on, since with it off
/// every choice would be ignored. The numbers always show, so they can be set
/// before the mode is switched on.
class ActivityModeSection extends StatefulWidget {
  const ActivityModeSection({super.key});

  @override
  State<ActivityModeSection> createState() => _ActivityModeSectionState();
}

class _ActivityModeSectionState extends State<ActivityModeSection> {
  /// On until storage says otherwise, matching how [NotificationSetting]
  /// reads a key that was never written.
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    ActivityModeSettings.enabled.load().then((value) {
      if (mounted) {
        setState(() => _enabled = value);
      }
    });
  }

  Future<void> _switch(bool value) async {
    await ActivityModeSettings.enabled.save(value);
    if (mounted) {
      setState(() => _enabled = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LocaleText(
          'profile.activity_mode.description',
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 12),
        ProfileToggleRow(
          labelKey: ActivityModeSettings.enabled.labelKey,
          value: _enabled,
          onChanged: _switch,
        ),
        if (_enabled) ...[
          const SizedBox(height: 4),
          const NotificationToggle(ActivityModeSettings.onOverview),
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
