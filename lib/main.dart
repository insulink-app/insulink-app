import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/base/page.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locale_notifier.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_bolus_state.dart';
import 'package:insulink/src/profile/profile_developer_state.dart';
import 'package:insulink/src/profile/profile_glucose_state.dart';
import 'package:insulink/src/profile/profile_language_state.dart';
import 'package:insulink/src/profile/profile_silent_state.dart';
import 'package:insulink/src/profile/profile_theme_state.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Locales.init(["de", "en"]);
  // Required so the UI isolate can exchange data with the foreground-service
  // isolate that owns the BLE connection.
  FlutterForegroundTask.initCommunicationPort();
  runApp(const InsulinkApp());
}

class InsulinkApp extends StatefulWidget {
  const InsulinkApp({super.key});

  @override
  State<InsulinkApp> createState() => _InsulinkAppState();
}

class _InsulinkAppState extends State<InsulinkApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    return FutureBuilder<
      ({
        String language,
        String theme,
        bool developer,
        ProfileGlucoseState glucose,
        ProfileBolusState bolus,
        ProfileSilentState silent,
      })
    >(
      future: _loadPreferences(),
      builder:
          (
            context,
            AsyncSnapshot<
              ({
                String language,
                String theme,
                bool developer,
                ProfileGlucoseState glucose,
                ProfileBolusState bolus,
                ProfileSilentState silent,
              })
            >
            snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            final language = snapshot.data?.language ?? "de";
            final theme = snapshot.data?.theme ?? "light";
            final developer = snapshot.data?.developer ?? false;
            final glucose = snapshot.data!.glucose;
            final bolus = snapshot.data!.bolus;
            final silent = snapshot.data!.silent;
            return MultiProvider(
              providers: [
                ChangeNotifierProvider(
                  create: (_) => ProfileLanguageState(language),
                ),
                ChangeNotifierProvider(create: (_) => ProfileThemeState(theme)),
                ChangeNotifierProvider(
                  create: (_) => ProfileDeveloperState(developer),
                ),
                ChangeNotifierProvider(create: (_) => glucose),
                ChangeNotifierProvider(create: (_) => bolus),
                ChangeNotifierProvider(create: (_) => silent),
                // Shared G7 read pipeline + service control, observed by the
                // overview and sensor pages.
                ChangeNotifierProvider(create: (_) => G7Controller()..init()),
              ],
              child: Consumer<ProfileThemeState>(
                builder: (context, themeState, _) => LocaleBuilder(
                  builder: (locale) => MaterialApp(
                    title: 'Insulink',
                    themeMode: themeState.themeMode,
                    theme: ThemeData(
                      useMaterial3: true,
                      primaryColor: Colors.black,
                      colorScheme: ColorScheme.light(
                        primary: Colors.indigo,
                        surface: Color(0xFFE8E8E8),
                      ),
                      appBarTheme: AppBarTheme(
                        backgroundColor: Color(0xFFFAFAFA),
                      ),
                      bottomNavigationBarTheme: BottomNavigationBarThemeData(
                        backgroundColor: Colors.white,
                      ),
                      scaffoldBackgroundColor: Color(0xFFFAFAFA),
                      dividerColor: Colors.black12,
                    ),
                    darkTheme: ThemeData(
                      useMaterial3: true,
                      primaryColor: Colors.white,
                      colorScheme: ColorScheme.dark(
                        primary: Colors.indigoAccent,
                        surface: Color(0xFF1E1E1E),
                        surfaceContainerHighest: Color(0xFF2A2A2A),
                      ),
                      appBarTheme: AppBarTheme(
                        backgroundColor: Color(0xFF1B1B1B),
                      ),
                      bottomNavigationBarTheme: BottomNavigationBarThemeData(
                        backgroundColor: Color(0xFF2A2A2A),
                      ),
                      scaffoldBackgroundColor: Color(0xFF1B1B1B),
                      dividerColor: Color(0xFF3B3B3B),
                    ),
                    home: ProductPage(),
                    debugShowCheckedModeBanner: false,
                    localizationsDelegates: Locales.delegates,
                    supportedLocales: Locales.supportedLocales,
                    locale: locale,
                  ),
                ),
              ),
            );
          },
    );
  }

  Future<
    ({
      String language,
      String theme,
      bool developer,
      ProfileGlucoseState glucose,
      ProfileBolusState bolus,
      ProfileSilentState silent,
    })
  >
  _loadPreferences() async {
    const storage = FlutterSecureStorage();
    final language =
        await storage.read(key: "language") ??
        PlatformDispatcher.instance.locale.languageCode;
    final theme =
        await storage.read(key: "theme") ??
        (PlatformDispatcher.instance.platformBrightness == Brightness.dark
            ? "dark"
            : "light");
    final developer = await ProfileDeveloperState.load();
    final glucose = await ProfileGlucoseState.load();
    final bolus = await ProfileBolusState.load();
    final silent = ProfileSilentState(await ProfileSilentState.load());
    return (
      language: language,
      theme: theme,
      developer: developer,
      glucose: glucose,
      bolus: bolus,
      silent: silent,
    );
  }
}
