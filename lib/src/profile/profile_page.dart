import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/account/profile_account_box.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/profile/profile_topic_page.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_sound_toggle.dart';
import 'package:insulink/src/profile/body/profile_body_selection.dart';
import 'package:insulink/src/profile/basal/profile_basal_selection.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_selection.dart';
import 'package:insulink/src/profile/notifications/profile_connection_toggle.dart';
import 'package:insulink/src/profile/developer/profile_developer_toggle.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_selection.dart';
import 'package:insulink/src/profile/language/profile_language_selection.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/profile/notifications/notification_threshold.dart';
import 'package:insulink/src/profile/notifications/notification_threshold_card.dart';
import 'package:insulink/src/profile/notifications/notification_toggle.dart';
import 'package:insulink/src/profile/notifications/profile_live_notification_toggle.dart';
import 'package:insulink/src/profile/notifications/profile_notification_toggle.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_band_toggle.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_horizon.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_toggle.dart';
import 'package:insulink/src/profile/silent/profile_silent_toggle.dart';
import 'package:insulink/src/sport/activity/sport_goals_editor.dart';
import 'package:insulink/src/profile/theme/profile_theme_selection.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

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
      icon: PhosphorIconsRegular.translate,
      searchKey: "profile.search.language",
      children: () => const [ProfileLanguageSelection()],
    ),
    (
      titleKey: "profile.theme",
      icon: PhosphorIconsRegular.palette,
      searchKey: "profile.search.theme",
      children: () => const [ProfileThemeSelection()],
    ),
    (
      titleKey: "profile.glucose",
      icon: PhosphorIconsRegular.drop,
      searchKey: "profile.search.glucose",
      children: () => const [ProfileGlucoseSelection()],
    ),
    (
      titleKey: "profile.bolus",
      icon: PhosphorIconsRegular.pill,
      searchKey: "profile.search.bolus",
      children: () => const [ProfileBolusSelection()],
    ),
    (
      titleKey: "profile.basal",
      icon: PhosphorIconsRegular.chartLine,
      searchKey: "profile.search.basal",
      children: () => const [ProfileBasalSelection()],
    ),
    (
      titleKey: "profile.body",
      icon: PhosphorIconsRegular.ruler,
      searchKey: "profile.search.body",
      children: () => const [ProfileBodySelection()],
    ),
    (
      titleKey: "sport.goals",
      icon: PhosphorIconsRegular.flag,
      searchKey: "profile.search.sport_goals",
      children: () => const [SportGoalsEditor()],
    ),
    (
      titleKey: "profile.notification",
      icon: PhosphorIconsRegular.bell,
      searchKey: "profile.search.notification",
      children: () => const [
        ProfileNotificationToggle(),
        SizedBox(height: 10),
        ProfileLiveNotificationToggle(),
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
      ],
    ),
    (
      titleKey: "profile.prediction",
      icon: PhosphorIconsRegular.chartLine,
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
      icon: PhosphorIconsRegular.bellSlash,
      searchKey: "profile.search.silent",
      children: () => const [ProfileSilentToggle()],
    ),
    (
      titleKey: "profile.developer",
      icon: PhosphorIconsRegular.code,
      searchKey: "profile.search.developer",
      children: () => const [ProfileDeveloperToggle()],
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
            icon: const Icon(PhosphorIconsRegular.arrowLeft),
            onPressed: _leave,
          ),
          title: LocaleText("profile.label"),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            _searchField(),
            const SizedBox(height: 16),
            if (!searching) ...[
              const ProfileAccountBox(),
              const SizedBox(height: 20),
            ],
            for (final topic in visible) _topicRow(topic),
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
        prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(PhosphorIconsRegular.x),
                onPressed: _search.clear,
              ),
      ),
    );
  }

  /// A tappable topic row: tinted icon, title and a chevron → its sub-page.
  Widget _topicRow(ProfileTopic topic) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProfileTopicPage(
                titleKey: topic.titleKey,
                children: topic.children(),
              ),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: scheme.onSurface.withValues(alpha: 0.07),
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(topic.icon, size: 22, color: scheme.onSurface),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: LocaleText(
                    topic.titleKey,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  PhosphorIconsRegular.caretRight,
                  size: 18,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
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
