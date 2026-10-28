import 'package:flutter/material.dart';
import 'package:insulink/src/activity_mode/activity_mode_section.dart';
import 'package:insulink/src/google_health/heart_rate_zones_editor.dart';
import 'package:insulink/src/google_health/profile_sleep_targets_editor.dart';
import 'package:insulink/src/nutrition/stats/nutrition_goals_editor.dart';
import 'package:insulink/src/profile/backup/profile_backup_export.dart';
import 'package:insulink/src/profile/basal/profile_basal_selection.dart';
import 'package:insulink/src/profile/battery/profile_battery_selection.dart';
import 'package:insulink/src/profile/body/profile_body_selection.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_selection.dart';
import 'package:insulink/src/profile/developer/developer_log_panel.dart';
import 'package:insulink/src/profile/developer/profile_developer_toggle.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_selection.dart';
import 'package:insulink/src/profile/language/profile_language_selection.dart';
import 'package:insulink/src/profile/night/night_mode_section.dart';
import 'package:insulink/src/profile/notifications/notification_threshold_card.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_sound_toggle.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_tone_picker.dart';
import 'package:insulink/src/profile/notifications/profile_notification_settings.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_band_toggle.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_horizon.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_toggle.dart';
import 'package:insulink/src/profile/security/profile_security_selection.dart';
import 'package:insulink/src/profile/silent/profile_silent_selection.dart';
import 'package:insulink/src/profile/theme/profile_theme_selection.dart';
import 'package:insulink/src/profile/tuning/basal_tuning_card.dart';
import 'package:insulink/src/profile/tuning/factor_tuning_card.dart';
import 'package:insulink/src/pump/loop/loop_micro_bolus_section.dart';
import 'package:insulink/src/pump/loop/loop_settings.dart';
import 'package:insulink/src/sport/activity/sport_goals_editor.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// One profile topic in the overview: title, icon, search synonyms and the
/// settings widgets shown on its sub-page.
typedef ProfileTopic = ({
  String titleKey,
  IconData icon,
  String searchKey,
  List<Widget> Function() children,
});

/// A titled panel of topics on the overview.
typedef ProfileTopicGroup = ({String titleKey, List<ProfileTopic> topics});

/// Every settings topic, in four groups: what doses insulin, what alerts,
/// the body and its goals, and the app itself. The search ignores the groups
/// and lists every match flat.
class ProfileTopicCatalog {
  const ProfileTopicCatalog();

  List<ProfileTopicGroup> get groups => [
    (titleKey: 'profile.group.therapy', topics: _therapy),
    (titleKey: 'profile.group.alerts', topics: _alerts),
    (titleKey: 'profile.group.body', topics: _body),
    (titleKey: 'profile.group.app', topics: _app),
  ];

  List<ProfileTopic> get all => [for (final group in groups) ...group.topics];

  /// The explanation of each page that has one, opened from the ⓘ in its app
  /// bar ([ProfileTopicPage.infoKey]).
  static const _infoKeys = {
    'profile.loop': 'profile.loop.description',
    'profile.activity_mode': 'profile.activity_mode.description',
    'profile.night': 'profile.night.description',
    'profile.body': 'profile.body.note',
    'profile.battery': 'profile.battery.description',
    'profile.security': 'profile.security.description',
  };

  String? infoFor(String titleKey) => _infoKeys[titleKey];

  List<ProfileTopic> get _therapy => [
    (
      titleKey: 'profile.glucose',
      icon: PhosphorIconsBold.drop,
      searchKey: 'profile.search.glucose',
      children: () => const [ProfileGlucoseSelection()],
    ),
    (
      titleKey: 'profile.bolus',
      icon: PhosphorIconsBold.pill,
      searchKey: 'profile.search.bolus',
      children: () => const [
        ProfileBolusSelection(),
        SizedBox(height: 20),
        FactorTuningCard(),
      ],
    ),
    (
      titleKey: 'profile.basal',
      icon: PhosphorIconsBold.chartLine,
      searchKey: 'profile.search.basal',
      children: () => const [
        ProfileBasalSelection(),
        SizedBox(height: 20),
        BasalTuningCard(),
      ],
    ),
    (
      titleKey: 'profile.loop',
      icon: PhosphorIconsBold.repeat,
      searchKey: 'profile.search.loop',
      children: () => const [
        NotificationThresholdCard(LoopSettings.suspendBelow),
        SizedBox(height: 10),
        NotificationThresholdCard(LoopSettings.maxRate),
        SizedBox(height: 10),
        NotificationThresholdCard(LoopSettings.maxIob),
        SizedBox(height: 16),
        LoopMicroBolusSection(),
      ],
    ),
    (
      titleKey: 'profile.activity_mode',
      icon: PhosphorIconsBold.personSimpleRun,
      searchKey: 'profile.search.activity_mode',
      children: () => const [ActivityModeSection()],
    ),
    (
      titleKey: 'profile.prediction',
      icon: PhosphorIconsBold.chartLine,
      searchKey: 'profile.search.prediction',
      children: () => const [
        ProfilePredictionToggle(),
        ProfilePredictionBandToggle(),
        SizedBox(height: 10),
        ProfilePredictionHorizon(),
      ],
    ),
  ];

  List<ProfileTopic> get _alerts => [
    (
      titleKey: 'profile.notification',
      icon: PhosphorIconsBold.bell,
      searchKey: 'profile.search.notification',
      children: () => const [ProfileNotificationSettings()],
    ),
    (
      titleKey: 'profile.alarmtone',
      icon: PhosphorIconsBold.speakerHigh,
      searchKey: 'profile.search.alarmtone',
      children: () => const [
        ProfileAlarmSoundToggle(),
        SizedBox(height: 20),
        ProfileAlarmTonePicker(),
      ],
    ),
    (
      titleKey: 'profile.night',
      icon: PhosphorIconsBold.moonStars,
      searchKey: 'profile.search.night',
      children: () => const [NightModeSection()],
    ),
    (
      titleKey: 'profile.silent',
      icon: PhosphorIconsBold.bellSlash,
      searchKey: 'profile.search.silent',
      children: () => const [ProfileSilentSelection()],
    ),
  ];

  List<ProfileTopic> get _body => [
    (
      titleKey: 'profile.body',
      icon: PhosphorIconsBold.ruler,
      searchKey: 'profile.search.body',
      children: () => const [ProfileBodySelection()],
    ),
    (
      titleKey: 'profile.sport_goals',
      icon: PhosphorIconsBold.flag,
      searchKey: 'profile.search.sport_goals',
      children: () => const [SportGoalsEditor()],
    ),
    (
      titleKey: 'profile.nutrition_goals',
      icon: PhosphorIconsBold.forkKnife,
      searchKey: 'profile.search.nutrition_goals',
      children: () => const [NutritionGoalsEditor()],
    ),
    (
      titleKey: 'google_health.hr_zones.title',
      icon: PhosphorIconsBold.heartbeat,
      searchKey: 'profile.search.hr_zones',
      children: () => const [HeartRateZonesEditor()],
    ),
    (
      titleKey: 'profile.sleep',
      icon: PhosphorIconsBold.moon,
      searchKey: 'profile.search.sleep',
      children: () => const [ProfileSleepTargetsEditor()],
    ),
  ];

  List<ProfileTopic> get _app => [
    (
      titleKey: 'profile.appearance',
      icon: PhosphorIconsBold.palette,
      searchKey: 'profile.search.appearance',
      children: () => const [
        ProfileLanguageSelection(),
        SizedBox(height: 20),
        ProfileThemeSelection(),
      ],
    ),
    (
      titleKey: 'profile.battery',
      icon: PhosphorIconsBold.batteryLow,
      searchKey: 'profile.search.battery',
      children: () => const [ProfileBatterySelection()],
    ),
    (
      titleKey: 'profile.security',
      icon: PhosphorIconsBold.fingerprint,
      searchKey: 'profile.search.security',
      children: () => const [ProfileSecuritySelection()],
    ),
    (
      titleKey: 'profile.backup',
      icon: PhosphorIconsBold.downloadSimple,
      searchKey: 'profile.search.backup',
      children: () => const [ProfileBackupExport()],
    ),
    (
      titleKey: 'profile.developer',
      icon: PhosphorIconsBold.code,
      searchKey: 'profile.search.developer',
      children: () => const [
        ProfileDeveloperToggle(),
        Spacer(),
        DeveloperLogPanel(),
      ],
    ),
  ];
}
