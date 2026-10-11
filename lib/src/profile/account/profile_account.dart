import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// Account-management calls for the signed-in user: backend log-out and rename,
/// each keeping local secure storage in step with the server.
class ProfileAccount {
  static const _storage = FlutterSecureStorage();

  /// Device-local flags that survive sign-out: not tied to the account and not
  /// held on the backend, so re-doing legal/onboarding or losing the chosen
  /// language/theme on every logout would be wrong. The same goes for the
  /// paired devices: the sensor and the Fitbit belong to the wearer, not the
  /// account, so they stay connected. Everything else is wiped.
  static const _keepOnLogout = {
    "legal_accepted",
    "onboarding_done",
    "language",
    "theme",
    "cgm.type",
    "g7.serial",
    "g7.pairing_code",
    "g7.resolved_key",
    "google_health.connected",
  };

  /// Key prefixes that survive sign-out.
  ///
  /// A paired pod MUST. Everything else wiped here comes back: glucose and
  /// settings from the account. A pod cannot. It answers only the controller
  /// that activated it, once, for good, so its key is the single piece of local
  /// state whose loss cannot be undone by any means, and a pod on the body with
  /// no key is one that keeps delivering insulin with nothing able to stop it.
  /// Deactivating it, which stops it first, is the only correct way to be rid
  /// of it.
  ///
  /// The sensor pairing (G7 session key, BLE id and metadata, Libre MAC, PIN
  /// and auth key) is kept so the sensor reconnects without a new pairing. Its
  /// readings are not: they would otherwise be uploaded into the next account.
  static const _keepPrefixes = [
    "pod.",
    "g7.session_key.",
    "g7.device_id.",
    "g7.info.",
    "g7.start.",
    "libre3.",
  ];

  /// Tells the backend to invalidate the session, then wipes the local data —
  /// account secrets, cached glucose/sport/Google Health data and the synced
  /// settings — so the next account signs in clean.
  /// Everything removed is re-fetched from the backend (glucose, settings);
  /// [_keepOnLogout] and [_keepPrefixes] remain. The network call is
  /// best-effort — the local wipe runs regardless, so logout works offline.
  Future<void> logout(BuildContext context) async {
    await Request.get(url: "/logout/").send(context);
    final keys = (await _storage.readAll()).keys.toList();
    for (final key in keys) {
      if (_keepOnLogout.contains(key) ||
          _keepPrefixes.any((prefix) => key.startsWith(prefix))) {
        continue;
      }
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
    final body = response.jsonObject;
    if (body == null) {
      return false;
    }
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
    return response.isApiSuccess;
  }
}
