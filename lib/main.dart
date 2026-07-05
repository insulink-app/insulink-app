import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/auth/auth_gate.dart';
import 'package:insulink/src/base/bouncy_scroll_behavior.dart';
import 'package:insulink/src/fitbit/fitbit_state.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locale_notifier.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/overview_layout.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/developer/profile_developer_state.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/profile/language/profile_language_state.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_state.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';
import 'package:insulink/src/profile/theme/profile_theme_state.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/activity/today_layout.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// The persisted settings the app needs before its first frame can render.
typedef AppPreferences = ({
  String language,
  String theme,
  bool developer,
  ProfileGlucoseState glucose,
  ProfileBolusState bolus,
  ProfileSilentState silent,
  ProfilePredictionState prediction,
  SportState sport,
  TrainingState training,
  CardioTrainingState cardio,
  FitbitState fitbit,
  TodayLayoutState todayLayout,
  OverviewLayoutState overviewLayout,
});

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

  /// Reloads the persisted preferences and rebuilds the provider tree. Used
  /// after sign-in so the settings just pulled from the backend take effect.
  static void reload(BuildContext context) {
    context.findAncestorStateOfType<_InsulinkAppState>()?._reload();
  }

  @override
  State<InsulinkApp> createState() => _InsulinkAppState();
}

class _InsulinkAppState extends State<InsulinkApp> with WidgetsBindingObserver {
  /// Loaded ONCE here, never in `build()`. Recreating the future on every root
  /// rebuild would reset the [FutureBuilder] to "waiting" (a blank frame =
  /// flicker) and tear down + rebuild the whole provider tree — re-running
  /// `G7Controller.init()` → `start()` → the foreground service/scan in a loop.
  late Future<AppPreferences> _preferences;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _preferences = _loadPreferences();
  }

  void _reload() {
    setState(() {
      _preferences = _loadPreferences();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppPreferences>(
      future: _preferences,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        return _providers(snapshot.data!);
      },
    );
  }

  /// Wraps the app in the shared state providers built from the loaded prefs.
  Widget _providers(AppPreferences prefs) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ProfileLanguageState(prefs.language),
        ),
        ChangeNotifierProvider(create: (_) => ProfileThemeState(prefs.theme)),
        ChangeNotifierProvider(
          create: (_) => ProfileDeveloperState(prefs.developer),
        ),
        ChangeNotifierProvider(create: (_) => prefs.glucose),
        ChangeNotifierProvider(create: (_) => prefs.bolus),
        ChangeNotifierProvider(create: (_) => prefs.silent),
        ChangeNotifierProvider(create: (_) => prefs.prediction),
        ChangeNotifierProvider(create: (_) => prefs.sport),
        ChangeNotifierProvider(create: (_) => prefs.training),
        ChangeNotifierProvider(create: (_) => prefs.cardio),
        ChangeNotifierProvider(create: (_) => prefs.fitbit),
        ChangeNotifierProvider(create: (_) => prefs.todayLayout),
        ChangeNotifierProvider(create: (_) => prefs.overviewLayout),
        // Step counter — only started when the Sport tab is opened
        // (ensureStarted), not here, to avoid forcing the permission/stream at
        // app start.
        ChangeNotifierProvider(create: (_) => SportActivityState()),
        // Shared G7 read pipeline + service control, observed by the overview
        // and sensor pages.
        ChangeNotifierProvider(create: (_) => G7Controller()..init()),
      ],
      child: _AppLifecycle(
        child: Consumer<ProfileThemeState>(
          builder: (context, themeState, _) =>
              LocaleBuilder(builder: (locale) => _app(themeState, locale)),
        ),
      ),
    );
  }

  Widget _app(ProfileThemeState themeState, Locale? locale) {
    return MaterialApp(
      title: 'Insulink',
      scrollBehavior: const BouncyScrollBehavior(),
      themeMode: themeState.themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: Locales.delegates,
      supportedLocales: Locales.supportedLocales,
      locale: locale,
    );
  }

  Future<AppPreferences> _loadPreferences() async {
    const storage = FlutterSecureStorage();
    final language =
        await storage.read(key: "language") ??
        PlatformDispatcher.instance.locale.languageCode;
    final theme =
        await storage.read(key: "theme") ??
        (PlatformDispatcher.instance.platformBrightness == Brightness.dark
            ? "dark"
            : "light");
    return (
      language: language,
      theme: theme,
      developer: await ProfileDeveloperState.load(),
      glucose: await ProfileGlucoseState.load(),
      bolus: await ProfileBolusState.load(),
      silent: ProfileSilentState(await ProfileSilentState.load()),
      prediction: await ProfilePredictionState.load(),
      sport: await SportState.load(),
      training: await TrainingState.load(),
      cardio: await CardioTrainingState.load(),
      fitbit: await FitbitState.load(),
      todayLayout: await TodayLayoutState.load(),
      overviewLayout: await OverviewLayoutState.load(),
    );
  }
}

/// Sits just below the provider tree so it can read the shared state, and runs
/// the once-per-open / on-resume side effects: start the live step counter (if
/// already permitted) so the overview counts without opening the Sport tab, and
/// re-read the pending auto-detected trainings the background service may have
/// written while we were away.
class _AppLifecycle extends StatefulWidget {
  const _AppLifecycle({required this.child});

  final Widget child;

  @override
  State<_AppLifecycle> createState() => _AppLifecycleState();
}

class _AppLifecycleState extends State<_AppLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    } else if (state == AppLifecycleState.paused) {
      // Final backup of today's steps before we're backgrounded/killed, so they
      // reach the account and survive a reinstall.
      if (mounted) {
        context.read<SportActivityState>().flushToday();
      }
    }
  }

  void _refresh() {
    if (!mounted) {
      return;
    }
    context.read<SportActivityState>().startIfPermitted();
    context.read<CardioTrainingState>().reloadPending();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
