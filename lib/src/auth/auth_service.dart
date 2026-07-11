import 'dart:convert';
import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' show Response;
import 'package:insulink/src/cgm/event_sync.dart';
import 'package:insulink/src/cgm/glucose_sync.dart';
import 'package:insulink/src/google_health/google_health_sync.dart';
import 'package:insulink/src/google_health/pulse_sync.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/nutrition/nutrition_sync.dart';
import 'package:insulink/src/sport/sport_sync.dart';

/// Talks to the backend `/signin/` and `/signup/` endpoints and persists the
/// returned tokens. Each method returns `null` on success, or a localization
/// key describing the failure for the caller to show.
class AuthService {
  static const _storage = FlutterSecureStorage();

  Future<String?> signIn(
    BuildContext context,
    String name,
    String password,
  ) async {
    final response = await Request.post(
      url: "/signin/",
      body: {"name": name, "password": password},
    ).send(context);
    final error = await _handle(response, "auth.error.invalid");
    if (error == null && context.mounted) {
      await ProfileSettings().pull(context);
    }
    if (error == null && context.mounted) {
      await GlucoseSync().pullHistory(context);
    }
    if (error == null && context.mounted) {
      await EventSync().pullHistory(context);
    }
    if (error == null && context.mounted) {
      await SportSync().pull(context);
    }
    if (error == null && context.mounted) {
      await NutritionSync().pull(context);
    }
    if (error == null && context.mounted) {
      await GoogleHealthSync().pull(context);
    }
    if (error == null && context.mounted) {
      await PulseSync().pull(context);
    }
    return error;
  }

  Future<String?> signUp(
    BuildContext context,
    String name,
    String password,
  ) async {
    final deviceFields = await _deviceFields();
    if (!context.mounted) {
      return "auth.error.network";
    }
    final response = await Request.post(
      url: "/signup/",
      body: {
        "name": name,
        "password": password,
        "legal_accepted": true,
        ...deviceFields,
      },
    ).send(context);
    return _handle(response, "auth.error.signup_failed");
  }

  /// Stores the tokens on success and returns null; otherwise the error key.
  Future<String?> _handle(Response? response, String invalidKey) async {
    if (response == null) {
      return "auth.error.network";
    }
    final body = jsonDecode(response.body);
    if (body["success"] != true) {
      return invalidKey;
    }
    await _storage.write(key: "user", value: "${body["user"]}");
    await _storage.write(key: "name", value: "${body["name"]}");
    await _storage.write(
      key: "authentication_token",
      value: body["authentication_token"],
    );
    await _storage.write(key: "refresh_token", value: body["refresh_token"]);
    return null;
  }

  /// Device metadata the backend stores against the new account, plus the
  /// language and any already-chosen settings the signup endpoint expects.
  Future<Map<String, Object>> _deviceFields() async {
    return {
      "language": await _storage.read(key: "language") ?? "en",
      "settings": jsonEncode(await ProfileSettings.collect()),
      ...await _findDeviceInfo(),
    };
  }

  Future<Map<String, String>> _findDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return {
        "device_id": await const AndroidId().getId() ?? "",
        "operating_system": "Android",
        "operating_system_version": androidInfo.version.release,
        "device_brand": androidInfo.brand,
        "device_model": androidInfo.model,
        "device_name": androidInfo.device,
      };
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return {
        "device_id": iosInfo.identifierForVendor ?? "",
        "operating_system": "IOS",
        "operating_system_version": iosInfo.systemVersion,
        "device_brand": "Apple",
        "device_model": iosInfo.utsname.machine,
        "device_name": iosInfo.name,
      };
    }
    return {};
  }
}
