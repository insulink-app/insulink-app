import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_bolus_selection.dart';
import 'package:insulink/src/profile/profile_connection_toggle.dart';
import 'package:insulink/src/profile/profile_developer_toggle.dart';
import 'package:insulink/src/profile/profile_glucose_selection.dart';
import 'package:insulink/src/profile/profile_language_selection.dart';
import 'package:insulink/src/profile/profile_live_notification_toggle.dart';
import 'package:insulink/src/profile/profile_notification_toggle.dart';
import 'package:insulink/src/profile/profile_silent_toggle.dart';
import 'package:insulink/src/profile/profile_theme_selection.dart';
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
          icon: Icon(CupertinoIcons.arrow_left),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        centerTitle: true,
      ),
      body: Container(
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
                        SizedBox(height: 10),
                        ProfileLiveNotificationToggle(),
                        SizedBox(height: 10),
                        ProfileConnectionToggle(),
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
                    Image.asset('assets/images/cute.png', width: 50),
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
      ),
    );
  }
}
