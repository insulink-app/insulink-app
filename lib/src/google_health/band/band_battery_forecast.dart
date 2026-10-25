import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/google_health/band/band_battery.dart';

/// How long the Fitbit Air's battery should last, extrapolated from how fast it
/// has drained since it last came off the charger.
///
/// Remembers the first reading of the current discharge; any reading that is
/// charging or higher than that start begins a new one. No estimate until the
/// band has lost [_minDrop] percent over at least [_minSpan], because the hourly
/// reads are whole percents and a shorter window would swing by days.
class BandBatteryForecast {
  const BandBatteryForecast(this._startPercent, this._startAt);

  static const _storageKey = 'band_battery_discharge_start';
  static const _minDrop = 3;
  static const _minSpan = Duration(hours: 3);

  final int _startPercent;
  final DateTime _startAt;

  static Future<BandBatteryForecast?> load() async {
    final parts = (await const FlutterSecureStorage().read(
      key: _storageKey,
    ))?.split(',');
    if (parts == null || parts.length != 2) {
      return null;
    }
    return BandBatteryForecast(
      int.parse(parts[0]),
      DateTime.fromMillisecondsSinceEpoch(int.parse(parts[1])),
    );
  }

  /// Folds a fresh reading in, starting a new discharge when needed.
  static Future<void> record(BandBattery battery) async {
    final start = await load();
    if (start != null &&
        battery.charging != true &&
        battery.percent <= start._startPercent) {
      return;
    }
    await const FlutterSecureStorage().write(
      key: _storageKey,
      value: '${battery.percent},${battery.readAt.millisecondsSinceEpoch}',
    );
  }

  /// Time left at the observed drain rate, or null while it cannot be told.
  Duration? remaining(BandBattery battery) {
    final drop = _startPercent - battery.percent;
    final span = battery.readAt.difference(_startAt);
    if (battery.charging == true || drop < _minDrop || span < _minSpan) {
      return null;
    }
    return span * (battery.percent / drop);
  }
}
