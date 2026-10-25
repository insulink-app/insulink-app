import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/google_health/band/band_battery.dart';
import 'package:insulink/src/google_health/band/band_battery_forecast.dart';

void main() {
  final start = DateTime(2026, 10, 24, 8);
  final forecast = BandBatteryForecast(80, start);

  BandBattery reading(int percent, Duration after, {bool? charging}) =>
      BandBattery(percent, charging, start.add(after));

  test('extrapolates the drain since the charger', () {
    final remaining = forecast.remaining(
      reading(60, const Duration(hours: 20)),
    );

    expect(remaining, const Duration(hours: 60));
  });

  test('stays quiet on too little drop, too short a span or charging', () {
    expect(forecast.remaining(reading(78, const Duration(hours: 10))), isNull);
    expect(forecast.remaining(reading(70, const Duration(hours: 2))), isNull);
    expect(
      forecast.remaining(
        reading(60, const Duration(hours: 20), charging: true),
      ),
      isNull,
    );
  });
}
