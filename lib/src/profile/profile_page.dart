import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_sound_toggle.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_selection.dart';
import 'package:insulink/src/profile/notifications/profile_connection_toggle.dart';
import 'package:insulink/src/profile/developer/profile_developer_toggle.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_selection.dart';
import 'package:insulink/src/profile/language/profile_language_selection.dart';
import 'package:insulink/src/profile/notifications/profile_live_notification_toggle.dart';
import 'package:insulink/src/profile/notifications/profile_notification_toggle.dart';
import 'package:insulink/src/profile/silent/profile_silent_toggle.dart';
import 'package:insulink/src/profile/theme/profile_theme_selection.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.arrow_left),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
      ),
      body: Container(
        margin: const EdgeInsets.symmetric(horizontal: 30),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _settings(),
                  Image.asset('assets/images/cute.png', width: 50),
                  _footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        _section("profile.language", [const ProfileLanguageSelection()]),
        _section("profile.theme", [const ProfileThemeSelection()]),
        _section("profile.glucose", [const ProfileGlucoseSelection()]),
        _section("profile.bolus", [const ProfileBolusSelection()]),
        _section("profile.notification", [
          const ProfileNotificationToggle(),
          const SizedBox(height: 10),
          const ProfileLiveNotificationToggle(),
          const SizedBox(height: 10),
          const ProfileConnectionToggle(),
          const SizedBox(height: 10),
          const ProfileAlarmSoundToggle(),
        ]),
        _section("profile.silent", [const ProfileSilentToggle()]),
        _section("profile.developer", [const ProfileDeveloperToggle()]),
      ],
    );
  }

  /// A titled settings group: the bold heading followed by its controls. The
  /// leading gap separates it from the section above.
  Widget _section(String titleKey, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 30),
        LocaleText(
          titleKey,
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
          textAlign: TextAlign.left,
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }

  Widget _footer() {
    return Column(
      children: [
        const SizedBox(height: 50),
        Divider(color: Colors.grey[300], height: 2),
        const SizedBox(height: 20),
        Align(alignment: Alignment.center, child: _version()),
        const SizedBox(height: 75),
      ],
    );
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
