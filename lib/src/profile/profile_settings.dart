import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:insulink/src/profile/battery/profile_battery_state.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/developer/profile_developer_state.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_sound_state.dart';
import 'package:insulink/src/profile/notifications/profile_connection_state.dart';
import 'package:insulink/src/profile/notifications/profile_live_notification_state.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/profile/notifications/notification_threshold.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_state.dart';
import 'package:insulink/src/pump/loop/loop_mode_backup.dart';
import 'package:insulink/src/pump/loop/loop_settings.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';
import 'package:insulink/src/overview/overview_layout.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';
import 'package:insulink/src/google_health/sleep_targets_state.dart';
import 'package:insulink/src/google_health/heart_rate_zones.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_tone_state.dart';
import 'package:insulink/src/profile/security/profile_security_state.dart';
import 'package:insulink/src/inventory/inventory_store.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_store.dart';
import 'package:insulink/src/nutrition/stats/nutrition_layout_state.dart';
import 'package:insulink/src/sport/activity/today_layout.dart';
import 'package:insulink/src/sport/sport_store.dart';

/// Syncs the user-tunable settings (glucose, bolus, every notification toggle
/// and alarm tone, silent mode, prediction, developer, body metrics, the box
/// layouts, the fingerprint gates, language and theme) with the account's
/// `settings` JSON blob on the backend. Left out on purpose: the LIVE automation
/// mode (a pod belongs to the phone that activated it; only a copy rides along,
/// see [LoopModeBackup]) and remembered view state such as the last chart range.
///
/// The blob is keyed by the same secure-storage keys the rest of the app reads,
/// so [pull] can write the server's values straight back into storage. The
/// backend REPLACES the whole blob on save, so [collect] always emits the
/// COMPLETE set (defaults filled in from each setting's loader).
class ProfileSettings {
  static const _storage = FlutterSecureStorage();

  /// The complete current settings, with defaults applied for anything the user
  /// hasn't changed yet. Values come from each setting's canonical loader so the
  /// defaults never drift from the rest of the app.
  static Future<Map<String, String>> collect() async {
    final glucose = await ProfileGlucoseState.load();
    final bolus = await ProfileBolusState.load();
    final prediction = await ProfilePredictionState.load();
    final silent = await ProfileSilentState.loadRaw();
    final battery = await ProfileBatteryState.loadRaw();
    const sport = SportStore();
    const nutrition = NutritionStore();
    final notifications =
        (await _storage.read(key: "notifications")) != "false";
    return {
      "glucose_unit": glucose.unit.name,
      "glucose_target_low": "${glucose.targetLow}",
      "glucose_target_high": "${glucose.targetHigh}",
      "glucose_urgent_low": "${glucose.urgentLow}",
      "glucose_low": "${glucose.low}",
      "glucose_high": "${glucose.high}",
      "glucose_urgent_high": "${glucose.urgentHigh}",
      "bolus_correction_factor": "${bolus.correctionFactor}",
      "bolus_carb_factor": "${bolus.carbFactor}",
      "bolus_max": "${bolus.maxBolus}",
      "bolus_insulin_duration_h": "${bolus.insulinDurationH}",
      "basal_profiles": await ProfileBasalState.loadRaw(),
      "notifications": "$notifications",
      "alarm_sound": "${await ProfileAlarmSoundState().load()}",
      "connection_lost_alert": "${await ProfileConnectionState().load()}",
      "live_glucose_notification":
          "${await ProfileLiveNotificationState().load()}",
      // The per-lifecycle notification toggles (default ON, stored under these
      // exact keys by NotificationSetting) — otherwise they wouldn't survive
      // logout/login like the other notification prefs.
      "sensor_expiry_alert": "${await NotificationSetting.expiry.load()}",
      "sensor_halftime_alert": "${await NotificationSetting.halftime.load()}",
      "training_detected_alert": "${await NotificationSetting.training.load()}",
      // Pod warnings: each toggle plus the number it fires at.
      "pod_expiry_alert": "${await NotificationSetting.podExpiry.load()}",
      "pod_expiry_hours": "${await NotificationThreshold.podExpiry.load()}",
      "pod_insulin_alert": "${await NotificationSetting.podInsulin.load()}",
      "pod_insulin_units": "${await NotificationThreshold.podInsulin.load()}",
      "pod_bolus_beep": "${await NotificationSetting.podBolusBeep.load()}",
      "pod_temp_basal_beep":
          "${await NotificationSetting.podTempBasalBeep.load()}",
      // The automated-delivery ceilings. The MODE is deliberately not here: a
      // pod belongs to the device that activated it, so which device is
      // automating is not an account-wide setting. The limits are, and a user
      // who has tuned them should not have to tune them again on a new phone.
      LoopSettings.suspendBelow.storageKey:
          "${await LoopSettings.suspendBelow.load()}",
      LoopSettings.maxRate.storageKey: "${await LoopSettings.maxRate.load()}",
      LoopSettings.maxIob.storageKey: "${await LoopSettings.maxIob.load()}",
      // Only a copy of the mode, read solely when a pod is adopted after a
      // reinstall, so it can come back engaged.
      LoopModeBackup.key: await const LoopModeBackup().loadRaw(),
      // Two booleans, not one enum: the panel coerces `silent_mode` to a bool
      // and writes it back, so the tone-only mute needs a key of its own.
      "silent_mode": "${silent.mode == SilentMode.all}",
      "silent_tones": "${silent.mode == SilentMode.tones}",
      // How long the mute runs (0 = until switched off) and the epoch-ms end it
      // was anchored to. Untyped by the panel, so they pass through untouched; a
      // lapsed mute collects as off.
      "silent_window_min": "${silent.window.windowMin}",
      "silent_until": "${silent.window.until}",
      // Battery saver: the mode as an enum string (unlike silent mode, no client
      // coerces this key to a bool), the picked window in minutes and the epoch-ms
      // end it was anchored to. A lapsed window collects as `off`, so a returning
      // device never adopts a saver whose time is up.
      "battery_saver_mode": battery.mode.name,
      "battery_saver_window_min": "${battery.window.windowMin}",
      "battery_saver_until": "${battery.window.until}",
      "developer": "${await ProfileDeveloperState.load()}",
      // Glucose-prediction overlay (on/off + band + horizon).
      "prediction_enabled": "${prediction.enabled}",
      "prediction_band": "${prediction.band}",
      "prediction_horizon": "${prediction.horizon}",
      // Keys must match SportStore's storage keys so pull() writes them back
      // where SportState reads them.
      "sport.stride_cm": "${await sport.loadStrideCm()}",
      "sport.height_cm": "${await sport.loadHeightCm()}",
      "sport.steps_goal": "${await sport.loadStepsGoal()}",
      "sport.distance_goal_m": "${await sport.loadDistanceGoalM()}",
      "sport.calories_goal": "${await sport.loadCaloriesGoal()}",
      "sport.weight_goal_kg": "${await sport.loadWeightGoalKg()}",
      // Nutrition goals — keys match NutritionStore so pull() writes them back
      // where NutritionState reads them.
      NutritionStore.goalKey: "${await nutrition.loadGoalMl()}",
      NutritionStore.carbsGoalKey: "${await nutrition.loadCarbsGoalG()}",
      NutritionStore.proteinGoalKey: "${await nutrition.loadProteinGoalG()}",
      // Box layouts (which boxes + order) of the Today grid and the overview,
      // so they survive logout/login.
      TodayLayoutState.key: await TodayLayoutState.loadRaw(),
      OverviewLayoutState.key: await OverviewLayoutState.loadRaw(),
      NutritionLayoutState.key: await NutritionLayoutState.loadRaw(),
      // Whether the glucose chart overlays logged meals (the detail page toggle).
      "chart_show_meals":
          "${(await _storage.read(key: 'chart_show_meals')) == 'true'}",
      // Sleep target windows (one JSON blob); pull() writes it straight back to
      // the same key SleepTargets reads.
      SleepTargets.key: await SleepTargets.loadRaw(),
      ...await _personalSettings(),
    };
  }

  /// The settings that used to stay on the phone: the fingerprint gates, each
  /// alarm's tone, the lock-screen and pre-warning notifications, the heart-rate
  /// zones, and language and theme. A new phone signing in starts with all of
  /// them. Language and theme are left out until the user picks one, so a pull
  /// never pins a device that still follows the system.
  static Future<Map<String, String>> _personalSettings() async {
    final security = ProfileSecurityState();
    final tones = await ProfileAlarmToneState().loadAll();
    final zones = await HeartRateZones.load();
    return {
      for (final action in GuardedAction.values)
        action.storageKey: "${await security.isGuarded(action)}",
      for (final entry in tones.entries)
        entry.key.toneStorageKey: entry.value.name,
      for (final setting in const [
        NotificationSetting.advisory,
        NotificationSetting.lockscreenGlucose,
      ])
        setting.storageKey: "${await setting.load()}",
      HeartRateZones.elevatedKey: "${zones.elevated}",
      HeartRateZones.highKey: "${zones.high}",
      for (final key in const ["language", "theme"])
        key: ?await _storage.read(key: key),
    };
  }

  /// Pushes the complete current settings to the backend (best-effort).
  ///
  /// The context is optional: it only buys the 403/417 handling a UI, and a
  /// caller that isn't a widget (see [ProfileSilentState.setSilent]) has none.
  Future<void> push(BuildContext? context) async {
    final settings = await collect();
    if (context != null && !context.mounted) {
      return;
    }
    await Request.post(
      url: "/user/settings/change/",
      body: {"settings": jsonEncode(settings)},
    ).send(context);
  }

  /// Loads the account's saved settings and writes them into local storage so a
  /// returning user adopts the settings stored against their account. Caller
  /// must rebuild the app afterwards for the in-memory state to pick them up.
  Future<void> pull(BuildContext? context) async {
    final response = await Request.get(
      url: "/user/settings/find/",
    ).send(context);
    final body = response.jsonObject;
    if (body == null) {
      return;
    }
    if (body["success"] != true) {
      return;
    }
    final settings = jsonDecode(body["settings"] as String);
    if (settings is! Map) {
      return;
    }
    for (final entry in settings.entries) {
      // Inventory moved to its own backend section (InventorySync); ignore a
      // stale copy still riding an old settings blob so it can't clobber it.
      if (entry.key == InventoryStore.itemsKey) {
        continue;
      }
      await _storage.write(key: "${entry.key}", value: "${entry.value}");
    }
  }
}
