import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether the ongoing foreground-service notification shows the current glucose
/// value + trend. Android requires the service to keep *a* notification, so when
/// off it falls back to a neutral "service running" text instead of hiding it.
///
/// Read fresh by the service isolate (which can't observe a notifier), so a
/// toggle takes effect without restarting the service.
class ProfileLiveNotificationState {
  static const _key = 'live_glucose_notification';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Default ON.
  Future<bool> load() async => (await _storage.read(key: _key)) != 'false';

  Future<void> save(bool v) => _storage.write(key: _key, value: '$v');
}
