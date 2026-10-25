import 'package:fitbit_air/fitbit_air.dart';
import 'package:flutter/widgets.dart';
import 'package:insulink/src/google_health/band/band_battery.dart';
import 'package:insulink/src/google_health/band/band_battery_forecast.dart';
import 'package:insulink/src/google_health/band/band_battery_watch.dart';

/// The Fitbit Air's battery as the UI shows it, provided app-wide so the
/// devices list, the header's red dot and the device page agree.
///
/// [load] is cheap (paired check plus the stored reading the service refreshes
/// hourly) and runs again on every return to the app, so the service's hourly
/// reading reaches the red dot; [refresh] reads the band and runs only when
/// its page opens.
class BandBatteryState extends ChangeNotifier with WidgetsBindingObserver {
  BandBatteryState() {
    WidgetsBinding.instance.addObserver(this);
  }

  bool paired = false;
  BandBattery? battery;
  BandBatteryForecast? _forecast;

  /// How long the battery should still last, null while it cannot be told.
  Duration? get remaining {
    final level = battery;
    return level == null ? null : _forecast?.remaining(level);
  }

  bool _disposed = false;

  /// At or below the warning line and not on the charger.
  bool get low {
    final level = battery;
    return paired &&
        level != null &&
        level.percent <= BandBatteryWatch.lowPercent &&
        level.charging != true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      load();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load() async {
    paired = await _airPaired();
    battery = paired ? await BandBattery.load() : null;
    _forecast = await BandBatteryForecast.load();
    _notify();
  }

  /// A fresh read; a failed one keeps the stored value.
  Future<void> refresh() async {
    if (!paired) {
      return;
    }
    battery = await BandBattery.readFresh() ?? battery;
    _forecast = await BandBatteryForecast.load();
    _notify();
  }

  /// A read can outlive the provider (an account reload rebuilds it), and a
  /// notify after dispose throws.
  void _notify() {
    if (!_disposed) {
      notifyListeners();
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
