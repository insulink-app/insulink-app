
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
  /// language/theme on every logout would be wrong. Everything else is wiped.
  static const _keepOnLogout = {
    "legal_accepted",
    "onboarding_done",
    "language",
    "theme",
  };

  /// A paired pod survives sign-out, and MUST.
  ///
  /// Everything else wiped here comes back: glucose from the account, settings
  /// from the account, a sensor by re-pairing. A pod cannot. It answers only the
  /// controller that activated it, once, for good, so its key is the single piece
  /// of local state whose loss cannot be undone by any means — and a pod on the
  /// body with no key is one that keeps delivering insulin with nothing able to
  /// stop it.
  ///
  /// The pod belongs to the DEVICE, not the account: signing into another
  /// account does not take the pod off the wearer's arm. Deactivating it, which
  /// stops it first, is the only correct way to be rid of it.
  static const _podPrefix = "pod.";

  /// Tells the backend to invalidate the session, then wipes the local data —
  /// account secrets, cached glucose/sport/Google Health data, the G7 sensor
  /// pairing and the synced settings — so the next account signs in clean.
  /// Everything removed is either re-fetched from the backend (glucose,
  /// settings) or re-paired on device; [_keepOnLogout] and a paired pod
  /// ([_podPrefix]) remain. The network call is
  /// best-effort — the local wipe runs regardless, so logout works offline.
  Future<void> logout(BuildContext context) async {
    await Request.get(url: "/logout/").send(context);
    final keys = (await _storage.readAll()).keys.toList();
    for (final key in keys) {
      if (_keepOnLogout.contains(key) || key.startsWith(_podPrefix)) {
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
