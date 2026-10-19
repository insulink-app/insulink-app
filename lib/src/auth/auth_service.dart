import 'dart:convert';
import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' show Response;
import 'package:insulink/src/auth/account_sync.dart';
import 'package:insulink/src/auth/data_key/data_key_sync.dart';
import 'package:insulink/src/auth/guest_mode.dart';
import 'package:insulink/src/auth/offline_handover.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// Talks to the backend `/signin/` and `/signup/` endpoints and persists the
/// returned tokens. Each method returns `null` on success, or a localization
/// key describing the failure for the caller to show.
class AuthService {
  static const _storage = FlutterSecureStorage();

  /// The shortest password the api accepts for a new account (its
  /// `User.MINIMUM_PASSWORD_LENGTH`), checked here first so the user hears it
  /// before a round trip.
  static const int minimumPasswordLength = 10;

  /// The api's error codes that mean something the user can act on.
  static const Map<int, String> _errorKeys = {
    1003: "auth.error.throttled",
    1005: "auth.error.password_short",
  };

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
      await const DataKeySync().adopt(context, password);
    }
    if (error == null && context.mounted) {
      await _adoptAccount(context);
    }
    return error;
  }

  Future<String?> signUp(
    BuildContext context,
    String name,
    String password,
  ) async {
    if (password.length < minimumPasswordLength) {
      return "auth.error.password_short";
    }
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
    final error = await _handle(response, "auth.error.signup_failed");
    if (error == null && context.mounted) {
      await const DataKeySync().adopt(context, password);
    }
    if (error == null && context.mounted && await const GuestMode().active) {
      if (context.mounted) {
        await _adoptAccount(context);
      }
    }
    return error;
  }

  /// Pulls the account into the local stores. Coming from [GuestMode], the
  /// pull merges with what was recorded offline and pushes it all up
  /// ([OfflineHandover]) instead of replacing it.
  Future<void> _adoptAccount(BuildContext context) async {
    final fromGuest = await const GuestMode().active;
    if (fromGuest) {
      await const OfflineHandover().prepare();
    }
    if (!context.mounted) {
      return;
    }
    await AccountSync().pullAll(context, withHistory: true);
    if (fromGuest) {
      await const OfflineHandover().finish();
    }
  }

  /// Stores the tokens on success and returns null; otherwise the error key.
  Future<String?> _handle(Response? response, String invalidKey) async {
    if (response == null) {
      return "auth.error.network";
    }
    final body = response.jsonObject;
    if (body == null) {
      return "auth.error.network";
    }
    if (body["success"] != true) {
      return _errorKeys[response.apiErrorCode] ?? invalidKey;
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
