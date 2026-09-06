import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/profile/notifications/notification_toggle.dart';
import 'package:provider/provider.dart';

/// Settings toggle for showing the glucose notification on the lock screen.
///
/// A [NotificationToggle] like the rest, plus the one thing this setting cannot
/// do without: the style lives in the notification channel, and a channel cannot
/// be changed once created, so the running service has to be moved onto the
/// other one before the switch means anything.
class ProfileLockscreenToggle extends StatelessWidget {
  const ProfileLockscreenToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return NotificationToggle(
      NotificationSetting.lockscreenGlucose,
      onApplied: () => context.read<CgmController>().applyNotificationStyle(),
    );
  }
}
