import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/request/request.dart';

/// Account-management calls for the signed-in user: backend log-out and rename,
/// each keeping local secure storage in step with the server.
class ProfileAccount {
  static const _storage = FlutterSecureStorage();

  /// Tells the backend to invalidate the session, then clears the local
  /// secrets. The network call is best-effort — the local clear runs regardless
  /// so the user is signed out even offline.
  Future<void> logout(BuildContext context) async {
    await Request.post(url: "/logout/").send(context);
    for (final key in [
      "user",
      "name",
      "authentication_token",
      "refresh_token",
    ]) {
      await _storage.delete(key: key);
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
}
