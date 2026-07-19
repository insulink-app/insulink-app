import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/libre3/libre3_glucose.dart';

/// Build a 29-byte one-minute reading with the given fields.
Uint8List _reading({
  required int lifeCount,
  required int rawGlucose,
  int rate = 0,
  int projectedX100 = 0,
  int bitfields = 0,
}) {
  final data = Uint8List(29);
  final view = ByteData.sublistView(data);
  view.setUint16(0, lifeCount, Endian.little);
  view.setUint16(2, rawGlucose, Endian.little);
  view.setInt16(4, rate, Endian.little);
  view.setUint16(8, projectedX100, Endian.little);
  data[14] = bitfields;
  return data;
}

void main() {
  group('Libre3GlucoseCodec.parseOneMinuteReading', () {
    test('decodes glucose, session clock, trend and prediction', () {
      final reading = Libre3GlucoseCodec.parseOneMinuteReading(
        _reading(
          lifeCount: 100, // minutes
          rawGlucose: 0x2000 | 120, // data-quality bit set, glucose 120
          rate: 15, // 0.15 mg/dL/min
          projectedX100: 13000, // 130 mg/dL
          bitfields: 0x1B,
        ),
      );
      expect(reading, isNotNull);
      expect(reading!.glucoseMgDl, 120);
      expect(reading.secsSinceStart, 100 * 60);
      expect(reading.predictedMgDl, 130);
      // 15/100 mg/dL/min = 0.15 → 1.5 tenths → rounds to 2.
      expect(reading.trendTenths, 2);
      expect(reading.state, 0x1B);
    });

    test('nulls the glucose when the error flag is set', () {
      final reading = Libre3GlucoseCodec.parseOneMinuteReading(
        _reading(lifeCount: 10, rawGlucose: 0x8000 | 100),
      );
      expect(reading!.glucoseMgDl, isNull);
    });

    test('nulls an out-of-range value', () {
      final reading = Libre3GlucoseCodec.parseOneMinuteReading(
        _reading(lifeCount: 10, rawGlucose: 20), // < 39
      );
      expect(reading!.glucoseMgDl, isNull);
    });

    test('treats the Int16 sentinel rate as flat', () {
      final reading = Libre3GlucoseCodec.parseOneMinuteReading(
        _reading(lifeCount: 10, rawGlucose: 100, rate: -32768),
      );
      expect(reading!.trendTenths, 0);
    });

    test('rejects a short packet', () {
      expect(Libre3GlucoseCodec.parseOneMinuteReading(Uint8List(10)), isNull);
    });
  });

  group('Libre3GlucoseCodec.parseHistorical', () {
    // start life count (LE16) ‖ plain uint16 glucose values, ascending +5 min.
    Uint8List packet(int start, List<int> glucose) {
      final data = Uint8List(2 + glucose.length * 2);
      final view = ByteData.sublistView(data);
      view.setUint16(0, start, Endian.little);
      for (var index = 0; index < glucose.length; index++) {
        view.setUint16(2 + index * 2, glucose[index], Endian.little);
      }
      return data;
    }

    test('steps the life count +5 min forward per value (Juggluco order)', () {
      final records = Libre3GlucoseCodec.parseHistorical(
        packet(100, [120, 122, 124]),
      );
      expect(records.map((r) => r.secsSinceStart), [
        100 * 60,
        105 * 60,
        110 * 60,
      ]);
      expect(records.map((r) => r.glucoseMgDl), [120, 122, 124]);
    });

    test('drops out-of-range values, keeps the rest', () {
      final records = Libre3GlucoseCodec.parseHistorical(
        packet(50, [120, 20, 130]), // 20 < 39 → dropped
      );
      expect(records.map((r) => r.glucoseMgDl), [120, 130]);
      // the dropped slot still advances the clock (index 1 skipped).
      expect(records.map((r) => r.secsSinceStart), [50 * 60, 60 * 60]);
    });

    test('empty on a too-short packet', () {
      expect(Libre3GlucoseCodec.parseHistorical(Uint8List(2)), isEmpty);
    });
  });

  group('Libre3GlucoseCodec.parseClinical', () {
    Uint8List hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ]);

    test('decodes lifeCount[0..2) + glucose[10..12) from a real capture', () {
      // Captured on-device: lifeCount 18835, glucose 0x00a8 = 168 at offset 10.
      final records = Libre3GlucoseCodec.parseClinical(
        hex('93499e067c47020f0000a8006900'),
      );
      expect(records.length, 1);
      expect(records.single.secsSinceStart, 18835 * 60);
      expect(records.single.glucoseMgDl, 168);
    });

    test('decodes several fixed-size records in one packet', () {
      // Two real captures concatenated: 18841=176, 18842=... (second one).
      final records = Libre3GlucoseCodec.parseClinical(
        hex('99492307e1465b0f0000b0007100' '9849f3066647170f0000ae007100'),
      );
      expect(records.map((r) => r.secsSinceStart), [18841 * 60, 18840 * 60]);
      expect(records.map((r) => r.glucoseMgDl), [176, 174]);
    });
  });
}
