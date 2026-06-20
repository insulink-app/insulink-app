import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_bolus_selection.dart';
import 'package:insulink/src/profile/profile_developer_toggle.dart';
import 'package:insulink/src/profile/profile_glucose_selection.dart';
import 'package:insulink/src/profile/profile_language_selection.dart';
import 'package:insulink/src/profile/profile_notification_toggle.dart';
import 'package:insulink/src/profile/profile_silent_toggle.dart';
import 'package:insulink/src/profile/profile_theme_selection.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ProfileBody extends ProductPageBody {
  final GlobalKey<_ProfilePageContentState> _key =
      GlobalKey<_ProfilePageContentState>();

  ProfileBody({super.key})
    : super(
        name: "profile.label",
        unselectedIcon: CupertinoIcons.person,
        selectedIcon: CupertinoIcons.person_fill,
      );

  @override
  Widget content(BuildContext context) {
    return ProfilePageContent(key: _key);
  }
}

class ProfilePageContent extends StatefulWidget {
  const ProfilePageContent({super.key});

  @override
  State<ProfilePageContent> createState() => _ProfilePageContentState();
}

class _ProfilePageContentState extends State<ProfilePageContent> {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 30),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 50),
                      LocaleText(
                        "profile.language",
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.left,
                      ),
                      SizedBox(height: 10),
                      ProfileLanguageSelection(),
                      SizedBox(height: 30),
                      LocaleText(
                        "profile.theme",
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.left,
                      ),
                      SizedBox(height: 10),
                      ProfileThemeSelection(),
                      SizedBox(height: 30),
                      LocaleText(
                        "profile.glucose",
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.left,
                      ),
                      SizedBox(height: 10),
                      ProfileGlucoseSelection(),
                      SizedBox(height: 30),
                      LocaleText(
                        "profile.bolus",
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.left,
                      ),
                      SizedBox(height: 10),
                      ProfileBolusSelection(),
                      SizedBox(height: 30),
                      LocaleText(
                        "profile.notification",
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.left,
                      ),
                      SizedBox(height: 10),
                      ProfileNotificationToggle(),
                      SizedBox(height: 30),
                      LocaleText(
                        "profile.silent",
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.left,
                      ),
                      SizedBox(height: 10),
                      ProfileSilentToggle(),
                      SizedBox(height: 30),
                      LocaleText(
                        "profile.developer",
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.left,
                      ),
                      SizedBox(height: 10),
                      ProfileDeveloperToggle(),
                    ],
                  ),
                  Column(
                    children: [
                      SizedBox(height: 50),
                      Divider(color: Colors.grey[300], height: 2),
                      SizedBox(height: 20),
                      Align(
                        alignment: Alignment.center,
                        child: FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snapshot) {
                            return Text(
                              Locales.string(
                                context,
                                "profile.version",
                                params: [snapshot.data?.version ?? ""],
                              ),
                              style: TextStyle(fontSize: 12),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 75),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
