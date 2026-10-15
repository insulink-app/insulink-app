import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/vehicle_stand_down.dart';

void main() {
  group('VehicleStandDown', () {
    test('three fast fixes under a vehicle label confirm a motorised ride', () {
      final standDown = VehicleStandDown();
      for (var fix = 0; fix < 3; fix++) {
        standDown.observe(ActivityKind.vehicle, 60);
      }
      expect(standDown.confirmed, isTrue);
    });

    test('a misread bike ride at bike speed is never confirmed', () {
      final standDown = VehicleStandDown();
      for (var fix = 0; fix < 50; fix++) {
        standDown.observe(ActivityKind.vehicle, 24);
      }
      expect(standDown.confirmed, isFalse);
    });

    test('fast fixes without a vehicle label never confirm', () {
      final standDown = VehicleStandDown();
      for (var fix = 0; fix < 5; fix++) {
        standDown.observe(ActivityKind.bike, 55);
      }
      expect(standDown.confirmed, isFalse);
    });

    test('stepping off (any other label) ends the confirmed ride', () {
      final standDown = VehicleStandDown();
      for (var fix = 0; fix < 3; fix++) {
        standDown.observe(ActivityKind.vehicle, 60);
      }
      standDown.observe(ActivityKind.walk, 0);
      expect(standDown.confirmed, isFalse);
    });
  });
}
