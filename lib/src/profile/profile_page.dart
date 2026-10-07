import 'package:flutter/material.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/base/list_row.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/account/profile_account_box.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/profile/profile_topic_page.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_sound_toggle.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_tone_picker.dart';
import 'package:insulink/src/profile/body/profile_body_selection.dart';
import 'package:insulink/src/profile/basal/profile_basal_selection.dart';
import 'package:insulink/src/profile/battery/profile_battery_selection.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_selection.dart';
import 'package:insulink/src/profile/notifications/profile_connection_toggle.dart';
import 'package:insulink/src/profile/developer/developer_log_panel.dart';
import 'package:insulink/src/profile/developer/profile_developer_toggle.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_selection.dart';
import 'package:insulink/src/profile/language/profile_language_selection.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/profile/notifications/notification_threshold.dart';
import 'package:insulink/src/profile/notifications/notification_threshold_card.dart';
import 'package:insulink/src/profile/tuning/basal_tuning_card.dart';
import 'package:insulink/src/profile/tuning/factor_tuning_card.dart';
import 'package:insulink/src/pump/loop/loop_settings.dart';
import 'package:insulink/src/profile/notifications/notification_toggle.dart';
import 'package:insulink/src/profile/notifications/profile_live_notification_toggle.dart';
import 'package:insulink/src/profile/notifications/profile_lockscreen_toggle.dart';
import 'package:insulink/src/profile/notifications/profile_notification_toggle.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_band_toggle.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_horizon.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_toggle.dart';
import 'package:insulink/src/profile/security/profile_security_selection.dart';
import 'package:insulink/src/profile/silent/profile_silent_selection.dart';
import 'package:insulink/src/google_health/heart_rate_zones_editor.dart';
import 'package:insulink/src/google_health/profile_sleep_targets_editor.dart';
import 'package:insulink/src/nutrition/stats/nutrition_goals_editor.dart';
import 'package:insulink/src/sport/activity/sport_goals_editor.dart';
import 'package:insulink/src/profile/theme/profile_theme_selection.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One profile topic in the overview: title, icon, search synonyms and the
/// settings widgets shown on its sub-page.
typedef ProfileTopic = ({
  String titleKey,
  IconData icon,
  String searchKey,
  List<Widget> Function() children,
});

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _search = TextEditingController();
  String _query = "";

  @override
  void initState() {
    super.initState();
    _search.addListener(
      () => setState(() => _query = _search.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The overview topics. Each links to a [ProfileTopicPage] with its settings.
  List<ProfileTopic> get _topics => [
    (
      titleKey: "profile.language",
      icon: PhosphorIconsBold.translate,
      searchKey: "profile.search.language",
      children: () => const [ProfileLanguageSelection()],
    ),
    (
      titleKey: "profile.theme",
      icon: PhosphorIconsBold.palette,
      searchKey: "profile.search.theme",
      children: () => const [ProfileThemeSelection()],
    ),
    (
      titleKey: "profile.glucose",
      icon: PhosphorIconsBold.drop,
      searchKey: "profile.search.glucose",
      children: () => const [ProfileGlucoseSelection()],
    ),
    (
      titleKey: "profile.bolus",
      icon: PhosphorIconsBold.pill,
      searchKey: "profile.search.bolus",
      children: () => const [
        ProfileBolusSelection(),
        SizedBox(height: 20),
        FactorTuningCard(),
      ],
    ),
    (
      titleKey: "profile.basal",
      icon: PhosphorIconsBold.chartLine,
      searchKey: "profile.search.basal",
      children: () => const [
        ProfileBasalSelection(),
        SizedBox(height: 20),
        BasalTuningCard(),
      ],
    ),
    (
      titleKey: "profile.body",
      icon: PhosphorIconsBold.ruler,
      searchKey: "profile.search.body",
      children: () => const [ProfileBodySelection()],
    ),
    (
      titleKey: "profile.sport_goals",
      icon: PhosphorIconsBold.flag,
      searchKey: "profile.search.sport_goals",
      children: () => const [SportGoalsEditor()],
    ),
    (
      titleKey: "profile.nutrition_goals",
      icon: PhosphorIconsBold.forkKnife,
      searchKey: "profile.search.nutrition_goals",
      children: () => const [NutritionGoalsEditor()],
    ),
    (
      titleKey: "google_health.hr_zones.title",
      icon: PhosphorIconsBold.heartbeat,
      searchKey: "profile.search.hr_zones",
      children: () => const [HeartRateZonesEditor()],
    ),
    (
      titleKey: "profile.sleep",
      icon: PhosphorIconsBold.moon,
      searchKey: "profile.search.sleep",
      children: () => const [ProfileSleepTargetsEditor()],
    ),
    (
      titleKey: "profile.notification",
      icon: PhosphorIconsBold.bell,
      searchKey: "profile.search.notification",
      children: () => const [
        ProfileNotificationToggle(),
        SizedBox(height: 10),
        ProfileLiveNotificationToggle(),
        SizedBox(height: 10),
        ProfileLockscreenToggle(),
        SizedBox(height: 10),
        ProfileConnectionToggle(),
        SizedBox(height: 10),
        NotificationToggle(NotificationSetting.expiry),
        SizedBox(height: 10),
        NotificationToggle(NotificationSetting.halftime),
        SizedBox(height: 10),
        NotificationToggle(NotificationSetting.training),
        SizedBox(height: 10),
        NotificationToggle(NotificationSetting.advisory),
        SizedBox(height: 10),
        ProfileAlarmSoundToggle(),
        SizedBox(height: 10),
        NotificationToggle(NotificationSetting.podExpiry),
        SizedBox(height: 10),
        NotificationThresholdCard(NotificationThreshold.podExpiry),
        SizedBox(height: 10),
        NotificationToggle(NotificationSetting.podInsulin),
        SizedBox(height: 10),
        NotificationThresholdCard(NotificationThreshold.podInsulin),
        NotificationToggle(NotificationSetting.podBolusBeep),
        SizedBox(height: 10),
        NotificationToggle(NotificationSetting.podTempBasalBeep),
      ],
    ),
    (
      titleKey: "profile.alarmtone",
      icon: PhosphorIconsBold.speakerHigh,
      searchKey: "profile.search.alarmtone",
      children: () => const [ProfileAlarmTonePicker()],
    ),
    (
      titleKey: "profile.loop",
      icon: PhosphorIconsBold.repeat,
      searchKey: "profile.search.loop",
      children: () => const [
        LocaleText("profile.loop.description", style: TextStyle(fontSize: 15)),
        SizedBox(height: 12),
        NotificationThresholdCard(LoopSettings.suspendBelow),
        SizedBox(height: 10),
        NotificationThresholdCard(LoopSettings.maxRate),
        SizedBox(height: 10),
        NotificationThresholdCard(LoopSettings.maxIob),
      ],
    ),
    (
      titleKey: "profile.prediction",
      icon: PhosphorIconsBold.chartLine,
      searchKey: "profile.search.prediction",
      children: () => const [
        ProfilePredictionToggle(),
        ProfilePredictionBandToggle(),
        SizedBox(height: 10),
        ProfilePredictionHorizon(),
      ],
    ),
    (
      titleKey: "profile.silent",
      icon: PhosphorIconsBold.bellSlash,
      searchKey: "profile.search.silent",
      children: () => const [ProfileSilentSelection()],
    ),
    (
      titleKey: "profile.battery",
      icon: PhosphorIconsBold.batteryLow,
      searchKey: "profile.search.battery",
      children: () => const [ProfileBatterySelection()],
    ),
    (
      titleKey: "profile.security",
      icon: PhosphorIconsBold.fingerprint,
      searchKey: "profile.search.security",
      children: () => const [ProfileSecuritySelection()],
    ),
    (
      titleKey: "profile.developer",
      icon: PhosphorIconsBold.code,
      searchKey: "profile.search.developer",
      children: () => const [
        ProfileDeveloperToggle(),
        Spacer(),
        DeveloperLogPanel(),
      ],
    ),
  ];

  bool _matches(ProfileTopic topic) {
    if (_query.isEmpty) {
      return true;
    }
    final corpus =
        '${Locales.string(context, topic.titleKey)} '
                '${Locales.string(context, topic.searchKey)}'
            .toLowerCase();
    return corpus.contains(_query);
  }

  /// Pushes the latest settings to the backend, then leaves the page. Funnels
  /// both the app-bar arrow and the system back gesture so a change always
  /// syncs. The push is fire-and-forget — leaving must never wait on the network.
  void _leave() {
    ProfileSettings().push(Navigator.of(context, rootNavigator: true).context);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.isNotEmpty;
    final visible = _topics.where(_matches).toList();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _leave();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(PhosphorIconsBold.arrowLeft),
            onPressed: _leave,
          ),
          title: LocaleText("profile.label"),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            InkSpace.panelMargin,
            12,
            InkSpace.panelMargin,
            40,
          ),
          children: [
            _searchField(),
            const SizedBox(height: 16),
            if (!searching) ...[
              const ProfileAccountBox(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SectionHeader(titleKey: 'profile.settings'),
              ),
            ],
            if (visible.isNotEmpty)
              InkPanel.list(
                radius: InkRadius.tile,
                rows: [for (final topic in visible) _topicRow(topic)],
              ),
            if (searching && visible.isEmpty) _noResults(),
            if (!searching) _footer(),
          ],
        ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      decoration: InputDecoration(
        hintText: Locales.string(context, "profile.search"),
        fillColor: context.ink.panel,
        prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(PhosphorIconsBold.x),
                onPressed: _search.clear,
              ),
      ),
    );
  }

  /// One settings row of the panel: icon disc, title and a chevron to its
  /// sub-page.
  Widget _topicRow(ProfileTopic topic) {
    return ListRow(
      icon: topic.icon,
      title: Locales.string(context, topic.titleKey),
      trailing: Icon(
        PhosphorIconsBold.caretRight,
        size: 18,
        color: context.ink.muted,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProfileTopicPage(
            titleKey: topic.titleKey,
            children: topic.children(),
          ),
        ),
      ),
    );
  }

  Widget _noResults() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Center(child: LocaleText("profile.search.empty")),
    );
  }

  Widget _footer() {
    return Column(children: [const SizedBox(height: 30), _version()]);
  }

  Widget _version() {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) => Text(
        Locales.string(
          context,
          "profile.version",
          params: [snapshot.data?.version ?? ""],
        ),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
