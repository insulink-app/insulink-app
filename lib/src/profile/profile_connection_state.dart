import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether to warn when no sensor reading arrives for 15 min while a sensor is
/// linked. Read fresh by the service isolate's watchdog (which can't observe a
/// notifier — same constraint as [ProfileSilentState]), so a toggle takes effect
/// without restarting the service.
class ProfileConnectionState {
  static const _key = 'connection_lost_alert';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Default ON — losing the glucose link is safety-relevant.
  Future<bool> load() async => (await _storage.read(key: _key)) != 'false';

  Future<void> save(bool v) => _storage.write(key: _key, value: '$v');
}
