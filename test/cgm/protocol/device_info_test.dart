import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/protocol/device_info.dart';

void main() {
  group('G7DeviceInfo.applyControl', () {
    test('0x4A transmitterVersion: firmware, software #, silicon, serial', () {
      final bytes = ByteData(20);
      bytes.setUint8(0, 0x4A);
      bytes.setUint8(2, 1);
      bytes.setUint8(3, 2);
      bytes.setUint8(4, 3);
      bytes.setUint8(5, 4);
      bytes.setUint32(6, 12345, Endian.little);
      bytes.setUint32(10, 678, Endian.little);
      // 6-byte little-endian serial = 0x0000_0000_002A = 42
      bytes.setUint8(14, 42);

      final info = G7DeviceInfo();
      expect(info.applyControl(bytes.buffer.asUint8List()), isTrue);
      expect(info.firmware, '1.2.3.4');
      expect(info.softwareNumber, 12345);
      expect(info.siliconVersion, 678);
      expect(info.serialNumber, '42');
      expect(info.hasAny, isTrue);
    });

    test('0x52 extended version: session/warmup length + algo/hw', () {
      final bytes = ByteData(15);
      bytes.setUint8(0, 0x52);
      bytes.setUint32(2, 907200, Endian.little);
      bytes.setUint16(6, 1800, Endian.little);
      bytes.setUint32(8, 9, Endian.little);
      bytes.setUint8(12, 3);
      bytes.setUint16(13, 10, Endian.little);

      final info = G7DeviceInfo();
      expect(info.applyControl(bytes.buffer.asUint8List()), isTrue);
      expect(info.sessionLengthSec, 907200);
      expect(info.warmupSec, 1800);
      expect(info.algorithmVersion, 9);
      expect(info.hardwareVersion, 3);
      expect(info.maxLifetimeDays, 10);
    });

    test('0x22 battery status: voltages, runtime, temperature', () {
      final bytes = ByteData(8);
      bytes.setUint8(0, 0x22);
      bytes.setUint16(2, 300, Endian.little);
      bytes.setUint16(4, 290, Endian.little);
      bytes.setUint8(6, 5);
      bytes.setInt8(7, -2);

      final info = G7DeviceInfo();
      expect(info.applyControl(bytes.buffer.asUint8List()), isTrue);
      expect(info.batteryVoltageA, 300);
      expect(info.batteryVoltageB, 290);
      expect(info.runtimeDays, 5);
      expect(info.temperatureC, -2);
    });

    test('0x32 calibration bounds: read-only status', () {
      final bytes = ByteData(20);
      bytes.setUint8(0, 0x32);
      bytes.setUint16(7, 110, Endian.little);
      bytes.setUint32(9, 4200, Endian.little);
      bytes.setUint8(13, 1);
      bytes.setUint8(14, 1);

      final info = G7DeviceInfo();
      expect(info.applyControl(bytes.buffer.asUint8List()), isTrue);
      expect(info.lastCalBgValue, 110);
      expect(info.lastCalTimeSec, 4200);
      expect(info.calProcessingStatus, 1);
      expect(info.calibrationsPermitted, isTrue);
      expect(info.hasCalibrationBounds, isTrue);
    });

    test('unknown opcode or too-short payload returns false', () {
      expect(
        G7DeviceInfo().applyControl(Uint8List.fromList([0x99, 0])),
        isFalse,
      );
      expect(
        G7DeviceInfo().applyControl(Uint8List.fromList([0x4A, 0])),
        isFalse,
      );
      expect(G7DeviceInfo().applyControl(Uint8List(0)), isFalse);
    });
  });

  test('toJson/fromJson round-trips every field', () {
    final info = G7DeviceInfo()
      ..firmware = '1.2.3.4'
      ..softwareNumber = 12345
      ..siliconVersion = 678
      ..serialNumber = '42'
      ..sessionLengthSec = 907200
      ..warmupSec = 1800
      ..algorithmVersion = 9
      ..hardwareVersion = 3
      ..maxLifetimeDays = 10
      ..batteryVoltageA = 300
      ..batteryVoltageB = 290
      ..runtimeDays = 5
      ..temperatureC = -2
      ..calibrationsPermitted = true
      ..lastCalBgValue = 110
      ..lastCalTimeSec = 4200
      ..calProcessingStatus = 1;

    final restored = G7DeviceInfo.fromJson(info.toJson());
    expect(restored.toJson(), info.toJson());
    expect(restored.serialNumber, '42');
    expect(restored.sessionLengthSec, 907200);
    expect(restored.calibrationsPermitted, isTrue);
  });

  group('g7AlgorithmStateKey', () {
    test('maps known states to locale keys', () {
      expect(g7AlgorithmStateKey(0x06), 'sensor.state.ok');
      expect(g7AlgorithmStateKey(0x02), 'sensor.state.warmup');
      expect(g7AlgorithmStateKey(0x0F), 'sensor.state.session_expired');
    });

    test('returns null for an unknown state', () {
      expect(g7AlgorithmStateKey(0xFF), isNull);
    });
  });
}
