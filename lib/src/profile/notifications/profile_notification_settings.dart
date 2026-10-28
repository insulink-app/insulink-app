import 'package:flutter/material.dart';
import 'package:insulink/src/base/info_button.dart';
import 'package:insulink/src/google_health/band/band_vibration_settings.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/profile/notifications/notification_threshold.dart';
import 'package:insulink/src/profile/notifications/notification_threshold_card.dart';
import 'package:insulink/src/profile/notifications/notification_toggle.dart';
import 'package:insulink/src/profile/notifications/profile_connection_toggle.dart';
import 'package:insulink/src/profile/notifications/profile_live_notification_toggle.dart';
import 'package:insulink/src/profile/notifications/profile_lockscreen_toggle.dart';
import 'package:insulink/src/profile/notifications/profile_notification_toggle.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The notification topic, sorted by what each switch is about instead of one
/// list of twenty: how the ongoing notification looks, then glucose, sensor,
/// pump, Fitbit Air and training.
class ProfileNotificationSettings extends StatelessWidget {
  const ProfileNotificationSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NotificationGroup('profile.notification_group.display', first: true, [
          ProfileNotificationToggle(),
          ProfileLiveNotificationToggle(),
          ProfileLockscreenToggle(),
        ]),
        _NotificationGroup('profile.notification_group.glucose', [
          ProfileConnectionToggle(),
          NotificationToggle(NotificationSetting.advisory),
        ]),
        _NotificationGroup('profile.notification_group.sensor', [
          NotificationToggle(NotificationSetting.expiry),
          NotificationToggle(NotificationSetting.halftime),
        ]),
        _NotificationGroup('profile.notification_group.pump', [
          NotificationToggle(NotificationSetting.podExpiry),
          NotificationThresholdCard(NotificationThreshold.podExpiry),
          NotificationToggle(NotificationSetting.podInsulin),
          NotificationThresholdCard(NotificationThreshold.podInsulin),
          NotificationToggle(NotificationSetting.podBolusBeep),
          NotificationToggle(NotificationSetting.podTempBasalBeep),
        ]),
        _NotificationGroup('profile.notification_group.band', [
          BandVibrationSettings(),
        ], infoKey: 'profile.band_vibration.legend'),
        _NotificationGroup('profile.notification_group.training', [
          NotificationToggle(NotificationSetting.training),
        ]),
      ],
    );
  }
}

/// A section header over its switches, 10 px apart.
class _NotificationGroup extends StatelessWidget {
  const _NotificationGroup(
    this.titleKey,
    this.children, {
    this.first = false,
    this.infoKey,
  });

  final String titleKey;
  final List<Widget> children;

  /// The group's explanation, behind an [InfoButton] in its header.
  final String? infoKey;

  /// The first group sits right under the app bar, without the section gap.
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SectionHeader(
            titleKey: titleKey,
            topGap: first ? 0 : InkSpace.sectionGap,
            actions: [
              if (infoKey case final infoKey?)
                InfoButton(titleKey: titleKey, bodyKey: infoKey),
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}
