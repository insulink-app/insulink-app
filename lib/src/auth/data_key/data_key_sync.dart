// The context is optional UI feedback threaded to Request, which forwards it to
// RequestReset; that guards `mounted` itself, as request.dart explains.
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/widgets.dart';
import 'package:insulink/src/auth/data_key/data_key.dart';
import 'package:insulink/src/auth/data_key/data_key_envelope.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// Keeps this device's [DataKey] in step with the one the account holds.
///
/// The password is only at hand while the user types it, so this runs at
/// sign-in, sign-up and a password change. A device that stays signed in from
/// before the key existed has none and keeps mirroring secrets in plain form,
/// exactly as before, until one of those moments comes.
class DataKeySync {
  const DataKeySync({
    this.envelope = const DataKeyEnvelope(),
    this.store = const DataKeyStore(),
  });

  /// Error code of `/user/key/find/` for an account without a key.
  static const int _noKeyCode = 1000;

  final DataKeyEnvelope envelope;
  final DataKeyStore store;

  /// Takes over the account's key, or gives the account its first one.
  ///
  /// A key left behind by an earlier account is dropped first. A new key is
  /// only created when the account has said it has none: one created after a
  /// failed lookup could replace a key whose sealed secrets are still on file.
  Future<void> adopt(BuildContext? context, String password) async {
    await store.forget();
    final account = await _fetch(context);
    if (account == null) {
      return;
    }
    if (account.envelope == null) {
      await _create(context, password);
      return;
    }
    final key = await envelope.unwrap(account.envelope!, password);
    if (key == null) {
      debugPrint('data key: the account key does not open with this password');
      return;
    }
    await store.save(key);
  }

  /// The key wrapped for [next], to send with the password change, or null when
  /// the change must not go ahead: the account's key could not be read, and
  /// changing the password anyway would lock it away for good.
  Future<RewrappedKey?> rewrap(
    BuildContext? context,
    String current,
    String next,
  ) async {
    final key = await store.load() ?? await _accountKey(context, current);
    if (key == null) {
      return null;
    }
    return RewrappedKey(key, await envelope.wrap(key, next));
  }

  /// The account's key opened with [password], a new one when the account has
  /// none, or null when the lookup failed or the key does not open.
  Future<DataKey?> _accountKey(BuildContext? context, String password) async {
    final account = await _fetch(context);
    if (account == null) {
      return null;
    }
    if (account.envelope == null) {
      return DataKey.generate();
    }
    return envelope.unwrap(account.envelope!, password);
  }

  Future<void> _create(BuildContext? context, String password) async {
    final key = DataKey.generate();
    final response = await Request.post(
      url: '/user/key/change/',
      body: {'password': password, 'key': await envelope.wrap(key, password)},
    ).send(context);
    if (response.isApiSuccess) {
      await store.save(key);
    }
  }

  /// What the account holds, or null when the lookup failed.
  Future<_AccountKey?> _fetch(BuildContext? context) async {
    final response = await Request.get(url: '/user/key/find/').send(context);
    if (response.isApiSuccess) {
      return _AccountKey(response.jsonObject!['key'] as String?);
    }
    if (response.apiErrorCode == _noKeyCode) {
      return const _AccountKey(null);
    }
    return null;
  }
}

/// A key and its envelope for the new password, saved once the change is in.
class RewrappedKey {
  const RewrappedKey(this.key, this.envelope);

  final DataKey key;
  final String envelope;
}

class _AccountKey {
  const _AccountKey(this.envelope);

  final String? envelope;
}
