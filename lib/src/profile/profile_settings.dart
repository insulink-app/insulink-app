import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/developer/profile_developer_state.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_sound_state.dart';
import 'package:insulink/src/profile/notifications/profile_connection_state.dart';
import 'package:insulink/src/profile/notifications/profile_live_notification_state.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_state.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';
import 'package:insulink/src/overview/overview_layout.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_store.dart';
import 'package:insulink/src/nutrition/stats/nutrition_layout_state.dart';
import 'package:insulink/src/sport/activity/today_layout.dart';
import 'package:insulink/src/sport/sport_store.dart';

/// Syncs the user-tunable settings (glucose, bolus, every notification toggle,
/// silent mode, prediction, developer, body metrics and the box layouts) with
/// the account's `settings` JSON blob on the backend. Only language and theme
/// are deliberately excluded — they're device-local view preferences.
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
      "silent_mode": "${await ProfileSilentState.load()}",
      "developer": "${await ProfileDeveloperState.load()}",
      // Glucose-prediction overlay (on/off + horizon).
      "prediction_enabled": "${prediction.enabled}",
      "prediction_horizon": "${prediction.horizon}",
      // Keys must match SportStore's storage keys so pull() writes them back
      // where SportState reads them.
      "sport.stride_cm": "${await sport.loadStrideCm()}",
      "sport.height_cm": "${await sport.loadHeightCm()}",
      "sport.steps_goal": "${await sport.loadStepsGoal()}",
      "sport.distance_goal_m": "${await sport.loadDistanceGoalM()}",
      "sport.calories_goal": "${await sport.loadCaloriesGoal()}",
      "sport.weight_goal_kg": "${await sport.loadWeightGoalKg()}",
      // Hydration daily goal (ml) — key matches NutritionStore so pull() writes
      // it back where NutritionState reads it.
      NutritionStore.goalKey: "${await nutrition.loadGoalMl()}",
      // Box layouts (which boxes + order) of the Today grid and the overview,
      // so they survive logout/login.
      TodayLayoutState.key: await TodayLayoutState.loadRaw(),
      OverviewLayoutState.key: await OverviewLayoutState.loadRaw(),
      NutritionLayoutState.key: await NutritionLayoutState.loadRaw(),
    };
  }

  /// Pushes the complete current settings to the backend (best-effort).
  Future<void> push(BuildContext context) async {
    final settings = await collect();
    if (!context.mounted) {
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
  Future<void> pull(BuildContext context) async {
    final response = await Request.get(
      url: "/user/settings/find/",
    ).send(context);
    if (response == null) {
      return;
    }
    final body = jsonDecode(response.body);
    if (body["success"] != true) {
      return;
    }
    final settings = jsonDecode(body["settings"] as String);
    if (settings is! Map) {
      return;
    }
    for (final entry in settings.entries) {
      await _storage.write(key: "${entry.key}", value: "${entry.value}");
    }
  }
}
