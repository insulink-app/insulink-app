import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/request/request.dart';

/// Account-management calls for the signed-in user: backend log-out and rename,
/// each keeping local secure storage in step with the server.
class ProfileAccount {
  static const _storage = FlutterSecureStorage();

  /// Device-local flags that survive sign-out: not tied to the account and not
  /// held on the backend, so re-doing legal/onboarding or losing the chosen
  /// language/theme on every logout would be wrong. Everything else is wiped.
  static const _keepOnLogout = {
    "legal_accepted",
    "onboarding_done",
    "language",
    "theme",
  };

  /// Tells the backend to invalidate the session, then wipes ALL local data —
  /// account secrets, cached glucose/sport/Google Health data, the G7 sensor pairing
  /// and the synced settings — so the next account signs in clean. Everything
  /// removed is either re-fetched from the backend (glucose, settings) or
  /// re-paired on device; only [_keepOnLogout] remains. The network call is
  /// best-effort — the local wipe runs regardless, so logout works offline.
  Future<void> logout(BuildContext context) async {
    await Request.get(url: "/logout/").send(context);
    final keys = (await _storage.readAll()).keys.toList();
    for (final key in keys) {
      if (!_keepOnLogout.contains(key)) {
        await _storage.delete(key: key);
      }
    }
  }

  /// Renames the account on the backend and, on success, persists the new name.
  /// Returns true when the change was accepted.
  Future<bool> rename(BuildContext context, String name) async {
    final response = await Request.post(
      url: "/name/change/",
      body: {"name": name},
    ).send(context);
    if (response == null) {
      return false;
    }
    final body = jsonDecode(response.body);
    if (body["success"] != true) {
      return false;
    }
    await _storage.write(key: "name", value: name);
    return true;
  }

  /// Changes the account password on the backend, verifying [current] against
  /// the stored hash server-side. Nothing is persisted locally — the password is
  /// never stored on device. Returns true when the change was accepted.
  Future<bool> changePassword(
    BuildContext context,
    String current,
    String next,
  ) async {
    final response = await Request.post(
      url: "/user/password/change/",
      body: {"password": current, "new_password": next},
    ).send(context);
    if (response == null) {
      return false;
    }
    return jsonDecode(response.body)["success"] == true;
  }
}
