import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/developer/profile_developer_state.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_sound_state.dart';
import 'package:insulink/src/profile/notifications/profile_connection_state.dart';
import 'package:insulink/src/profile/notifications/profile_live_notification_state.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/sport/sport_store.dart';

/// Syncs the user-tunable settings (glucose, bolus, notifications, silent,
/// developer) with the account's `settings` JSON blob on the backend. Language
/// and theme are device-local and deliberately excluded.
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
    const sport = SportStore();
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
      "silent_mode": "${await ProfileSilentState.load()}",
      "developer": "${await ProfileDeveloperState.load()}",
      // Keys must match SportStore's storage keys so pull() writes them back
      // where SportState reads them.
      "sport.stride_cm": "${await sport.loadStrideCm()}",
      "sport.height_cm": "${await sport.loadHeightCm()}",
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
