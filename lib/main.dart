import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/auth/account_sync.dart';
import 'package:insulink/src/auth/auth_gate.dart';
import 'package:insulink/src/base/bouncy_scroll_behavior.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/inventory/inventory_state.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_notifier.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/overview_layout.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/developer/profile_developer_state.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/profile/language/profile_language_state.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_state.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';
import 'package:insulink/src/profile/theme/profile_theme_state.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_layout_state.dart';
import 'package:insulink/src/sport/activity/health_importer.dart';
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
  ProfileBasalState basal,
  ProfileSilentState silent,
  ProfilePredictionState prediction,
  SportState sport,
  TrainingState training,
  CardioTrainingState cardio,
  GoogleHealthState health,
  TodayLayoutState todayLayout,
  OverviewLayoutState overviewLayout,
  NutritionState nutrition,
  FoodState food,
  MealState meals,
  NutritionLayoutState nutritionLayout,
  InventoryState inventory,
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
  /// Null until the first load finishes — that is the only time the app has
  /// nothing to render. A [_reload] KEEPS the previous value on screen while it
  /// re-reads, so adopting pulled settings never flashes back to the splash.
  AppPreferences? _preferences;

  /// Bumped on every completed [_reload] to key the DATA-provider subtree, so it
  /// is rebuilt from scratch instead of reused.
  ///
  /// Load-bearing: a provider's `create` runs once per ELEMENT, not per build.
  /// Without a fresh key the reloaded state objects are constructed and then
  /// dropped on the floor — the account's settings would only reach the app on
  /// the next cold start. The key sits BELOW both [CgmController] AND the
  /// [MaterialApp] (see [_dataProviders]): a reload must never restart the read
  /// pipeline (CLAUDE.md scan throttle) NOR tear down the [Navigator] — doing so
  /// dropped any pushed page and flashed the whole scaffold a second into launch
  /// when the account pull arrived.
  int _generation = 0;

  /// The theme provider lives ABOVE [MaterialApp] (a reload must not remount the
  /// app), so it is created ONCE and updated in place by [_reload] instead of
  /// being recreated per generation.
  ProfileThemeState? _themeState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _start();
  }

  /// Render from local storage FIRST, then sync. The account pull used to sit in
  /// front of the first frame, which put a cold DNS+TLS handshake plus 14 round
  /// trips between the splash and the app.
  Future<void> _start() async {
    await _reload();
    await _pullAccount();
  }

  Future<void> _reload() async {
    final preferences = await _loadPreferences();
    if (!mounted) {
      return;
    }
    final themeState = _themeState;
    if (themeState == null) {
      _themeState = ProfileThemeState(preferences.theme);
    } else {
      themeState.setThemeMode(
        preferences.theme == "dark" ? ThemeMode.dark : ThemeMode.light,
      );
    }
    setState(() {
      _preferences = preferences;
      _generation++;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The state that does NOT come from [AppPreferences] lives above the loading
  /// point: it survives a [_reload], and it starts during the splash instead of
  /// after it. Keeping [CgmController] up here is load-bearing — a rebuilt one
  /// starts with an empty restart cooldown and can fire a back-to-back service
  /// restart, which trips Android's scan throttle (~30 min without devices, see
  /// CLAUDE.md).
  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    return MultiProvider(
      providers: [
        // Step counter — only started when the Sport tab is opened
        // (ensureStarted), not here, to avoid forcing the permission/stream at
        // app start.
        ChangeNotifierProvider(create: (_) => SportActivityState()),
        // Shared G7 read pipeline + service control, observed by the overview
        // and sensor pages.
        ChangeNotifierProvider(create: (_) => CgmController()..init()),
      ],
      child: preferences == null
          ? const _SplashHold()
          : _rootApp(preferences),
    );
  }

  /// The app shell that SURVIVES an account-pull reload: the theme provider,
  /// [MaterialApp] and its [Navigator] are built once and stay mounted. Only the
  /// data providers below (see [_dataProviders]) rebuild per generation, so a
  /// mid-session pull refreshes the pulled settings/history without flashing the
  /// scaffold or dropping a page the user had just opened.
  Widget _rootApp(AppPreferences prefs) {
    return ChangeNotifierProvider<ProfileThemeState>.value(
      value: _themeState!,
      child: Consumer<ProfileThemeState>(
        builder: (context, themeState, _) =>
            LocaleBuilder(builder: (locale) => _app(prefs, themeState, locale)),
      ),
    );
  }

  Widget _app(
    AppPreferences prefs,
    ProfileThemeState themeState,
    Locale? locale,
  ) {
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
      builder: (context, child) => _dataProviders(prefs, child!),
    );
  }

  /// The reloadable state providers, keyed by [_generation] so a pull rebuilds
  /// them from the freshly pulled storage. It wraps the [MaterialApp]'s
  /// [Navigator] (`child`) rather than sitting above [MaterialApp], so the
  /// Navigator — which carries its own GlobalKey — keeps its route stack across
  /// the rebuild while the providers below it adopt the new state.
  Widget _dataProviders(AppPreferences prefs, Widget child) {
    return MultiProvider(
      key: ValueKey(_generation),
      providers: [
        ChangeNotifierProvider(
          create: (_) => ProfileLanguageState(prefs.language),
        ),
        ChangeNotifierProvider(
          create: (_) => ProfileDeveloperState(prefs.developer),
        ),
        ChangeNotifierProvider(create: (_) => prefs.glucose),
        ChangeNotifierProvider(create: (_) => prefs.bolus),
        ChangeNotifierProvider(create: (_) => prefs.basal),
        ChangeNotifierProvider(create: (_) => prefs.silent),
        ChangeNotifierProvider(create: (_) => prefs.prediction),
        ChangeNotifierProvider(create: (_) => prefs.sport),
        ChangeNotifierProvider(create: (_) => prefs.training),
        ChangeNotifierProvider(create: (_) => prefs.cardio),
        ChangeNotifierProvider(create: (_) => prefs.health..init()),
        ChangeNotifierProvider(create: (_) => prefs.todayLayout),
        ChangeNotifierProvider(create: (_) => prefs.overviewLayout),
        ChangeNotifierProvider(create: (_) => prefs.nutrition),
        ChangeNotifierProvider(create: (_) => prefs.food),
        ChangeNotifierProvider(create: (_) => prefs.meals),
        ChangeNotifierProvider(create: (_) => prefs.nutritionLayout),
        ChangeNotifierProvider(create: (_) => prefs.inventory),
      ],
      child: _AppLifecycle(child: child),
    );
  }

  /// Adopts what the account holds server-side (settings changed on the web
  /// panel or another device) AFTER the app is already on screen. It takes as
  /// long as it takes — no time budget, because nothing waits for it.
  ///
  /// Every branch writes into the same secure storage the preferences are read
  /// from, so comparing storage across the pull says whether anything that feeds
  /// the provider tree actually arrived: an unchanged account leaves the running
  /// tree untouched, and only a real settings change costs a [_reload].
  ///
  /// Never throws: a failed sync must only mean "keep the local data", and the
  /// next start retries.
  Future<void> _pullAccount() async {
    const storage = FlutterSecureStorage();
    if ((await storage.read(key: "authentication_token") ?? "").isEmpty) {
      return;
    }
    try {
      final before = _preferenceKeys(await storage.readAll());
      await AccountSync().pullAll(null);
      if (!mapEquals(before, _preferenceKeys(await storage.readAll()))) {
        await _reload();
      }
    } catch (exception) {
      debugPrint("account sync skipped: $exception");
    }
  }

  /// The storage entries that feed [AppPreferences], with the CGM data dropped.
  ///
  /// [_reload] rebuilds the whole provider tree, so it must only fire for a real
  /// settings change. The glucose archive/live keys (`g7.*`) are NOT preferences
  /// — [CgmController], above the reload point, owns them — yet the account pull
  /// rewrites the glucose history on EVERY launch. Comparing the whole store
  /// therefore reloaded the entire app a second time on every start (the second
  /// hitch on open). Ignoring the CGM keys leaves the compare to the settings the
  /// reload actually adopts.
  Map<String, String> _preferenceKeys(Map<String, String> all) {
    return {
      for (final entry in all.entries)
        if (!entry.key.startsWith("g7.")) entry.key: entry.value,
    };
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
      basal: await ProfileBasalState.load(),
      silent: ProfileSilentState(await ProfileSilentState.load()),
      prediction: await ProfilePredictionState.load(),
      sport: await SportState.load(),
      training: await TrainingState.load(),
      cardio: await CardioTrainingState.load(),
      health: await GoogleHealthState.load(),
      todayLayout: await TodayLayoutState.load(),
      overviewLayout: await OverviewLayoutState.load(),
      nutrition: await NutritionState.load(),
      food: await FoodState.load(),
      meals: await MealState.load(),
      nutritionLayout: await NutritionLayoutState.load(),
      inventory: await InventoryState.load(),
    );
  }
}

/// Fills the screen while the preferences load. Flutter tears the native splash
/// down as soon as it paints its FIRST frame, so an empty widget there is a
/// visible black flash between splash and app. Painting the scaffold background
/// makes that frame indistinguishable from the app that follows.
///
/// The persisted theme is exactly what is still being loaded, so this goes by
/// the OS brightness — the same fallback `_loadPreferences` uses when no theme
/// is stored.
class _SplashHold extends StatelessWidget {
  const _SplashHold();

  @override
  Widget build(BuildContext context) {
    final dark =
        PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    return ColoredBox(
      color: dark
          ? AppTheme.dark.scaffoldBackgroundColor
          : AppTheme.light.scaffoldBackgroundColor,
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
    unawaited(_refreshHealth());
  }

  /// Refreshes the Google Health metrics and, while connected, imports today's
  /// steps/distance/calories into the Today tiles — so a relaunch or resume
  /// updates them without waiting for the Sport tab to be opened. Sequential:
  /// the `health` plugin has a single activity-result channel, so the metrics
  /// refresh and the import must not overlap.
  Future<void> _refreshHealth() async {
    final health = context.read<GoogleHealthState>();
    final sport = context.read<SportState>();
    final activity = context.read<SportActivityState>();
    await health.refreshIfConnected();
    if (!mounted || !health.connected) {
      return;
    }
    await HealthImporter().import(sport, activity);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
