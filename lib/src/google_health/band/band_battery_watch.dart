import 'package:fitbit_air/fitbit_air.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/google_health/band/band_battery.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';

/// Reads the Fitbit Air's battery once an hour from the service watchdog and
/// warns once per discharge when it runs low.
///
/// Hourly because every read opens a secure session next to Google Health's
/// and briefly takes the band's channel from it. The "already warned" flag is
/// persisted, so a restarted service does not warn again for the same
/// discharge; charging or climbing back above the line re-arms it.
class BandBatteryWatch {
  BandBatteryWatch(this._notifyLow);

  /// ponytail: fixed line, a threshold setting when someone asks for one.
  static const lowPercent = 20;
  static const _readEvery = Duration(hours: 1);
  static const _warnedKey = 'band_battery_low_warned';

  /// Posts the warning; false when it was held back (silent mode), so it is
  /// not marked as given.
  final Future<bool> Function(int percent) _notifyLow;
  DateTime? _lastReadAt;
  bool _reading = false;

  /// One watchdog tick: a read when one is due, then the warning if needed.
  Future<void> tick() async {
    final last = _lastReadAt;
    if (_reading || (last != null && DateTime.now().difference(last) < _readEvery)) {
      return;
    }
    _reading = true;
    _lastReadAt = DateTime.now();
    try {
      await _readAndWarn();
    } finally {
      _reading = false;
    }
  }

  Future<void> _readAndWarn() async {
    if (!await _airPaired()) {
      return;
    }
    final battery = await BandBattery.readFresh();
    if (battery == null) {
      return;
    }
    const storage = FlutterSecureStorage();
    if (battery.percent > lowPercent || battery.charging == true) {
      await storage.delete(key: _warnedKey);
      return;
    }
    if (await storage.read(key: _warnedKey) != null || !await NotificationSetting.bandBatteryLow.load()) {
      return;
    }
    if (await _notifyLow(battery.percent)) {
      await storage.write(key: _warnedKey, value: 'true');
    }
  }

  Future<bool> _airPaired() async {
    try {
      return await FitbitAir.isAirPaired();
    } catch (_) {
      return false;
    }
  }
}
