import 'package:fitbit_air/fitbit_air.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The Fitbit Air's last known battery level, kept in secure storage so the
/// service isolate's hourly read and the device page share one value.
class BandBattery {
  const BandBattery(this.percent, this.charging, this.readAt);

  static const _storageKey = 'band_battery';

  final int percent;

  /// Null when the band did not say.
  final bool? charging;
  final DateTime readAt;

  /// The stored reading, or null if the band was never read.
  static Future<BandBattery?> load() async {
    final raw = await const FlutterSecureStorage().read(key: _storageKey);
    final parts = raw?.split(',');
    if (parts == null || parts.length != 3) {
      return null;
    }
    return BandBattery(
      int.parse(parts[0]),
      parts[1].isEmpty ? null : parts[1] == 'true',
      DateTime.fromMillisecondsSinceEpoch(int.parse(parts[2])),
    );
  }

  /// Reads the band now and stores the result; null when it cannot be reached.
  /// The plugin opens a short secure session (~3 s) for this, so call it on
  /// demand or hourly, never in a loop.
  static Future<BandBattery?> readFresh() async {
    try {
      final reading = await FitbitAir.readBattery();
      final battery = BandBattery(reading.percent, reading.onCharger, DateTime.now());
      await battery._save();
      return battery;
    } catch (error) {
      debugPrint('[band] battery read failed: $error');
      return null;
    }
  }

  Future<void> _save() => const FlutterSecureStorage().write(
    key: _storageKey,
    value: '$percent,${charging ?? ''},${readAt.millisecondsSinceEpoch}',
  );
}
