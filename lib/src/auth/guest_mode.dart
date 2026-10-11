import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Using the app without an account: everything is read, recorded and kept on
/// the device, and [Request] sends nothing that needs one. Signing in later
/// ends it and hands the collected data to the account (`OfflineHandover`).
class GuestMode {
  static const _storage = FlutterSecureStorage();
  static const _key = 'guest_mode';

  const GuestMode();

  Future<bool> get active async => await _storage.read(key: _key) == 'true';

  Future<void> enter() => _storage.write(key: _key, value: 'true');

  Future<void> leave() => _storage.delete(key: _key);
}
