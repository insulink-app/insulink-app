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
}
