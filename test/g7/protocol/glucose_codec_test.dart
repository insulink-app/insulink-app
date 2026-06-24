import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/g7/protocol/glucose.dart';

/// Builds a 19-byte live-EGV packet (opcode 0x4E) per the documented layout.
Uint8List egvPacket({
  int secs = 3600,
  int sequence = 5,
  int age = 30,
  int mgdlField = 120,
  int state = 6,
  int trend = 2,
  int predictedField = 130,
}) {
  final bytes = ByteData(19);
  bytes.setUint8(0, 0x4E);
  bytes.setInt32(2, secs, Endian.little);
  bytes.setUint16(6, sequence, Endian.little);
  bytes.setUint16(10, age, Endian.little);
  bytes.setUint16(12, mgdlField, Endian.little);
  bytes.setInt8(14, state);
  bytes.setInt8(15, trend);
  bytes.setUint16(16, predictedField, Endian.little);
  return bytes.buffer.asUint8List();
}

/// Builds one 9-byte backfill record.
Uint8List backfillRecord({
  required int secs,
  required int mgdl,
  required int type,
  int trend = 0,
}) {
  final bytes = ByteData(9);
  bytes.setInt32(0, secs, Endian.little);
  bytes.setInt16(4, mgdl, Endian.little);
  bytes.setUint8(6, type);
  bytes.setUint8(7, 0);
  bytes.setInt8(8, trend);
  return bytes.buffer.asUint8List();
}

void main() {
  group('G7GlucoseCodec.parseEgv', () {
    test('decodes a valid EGV packet', () {
      final reading = G7GlucoseCodec.parseEgv(egvPacket())!;
      expect(reading.secsSinceStart, 3600);
      expect(reading.sequence, 5);
      expect(reading.age, 30);
      expect(reading.glucoseMgDl, 120);
      expect(reading.state, 6);
      expect(reading.trendTenths, 2);
      expect(reading.trendMgDlPerMin, closeTo(0.2, 1e-9));
      expect(reading.predictedMgDl, 130);
      expect(reading.isValid, isTrue);
    });

    test('masks the 12-bit mgdl field (ignores the top 4 donly bits)', () {
      final reading = G7GlucoseCodec.parseEgv(
        egvPacket(mgdlField: 0xF000 | 120),
      )!;
      expect(reading.glucoseMgDl, 120);
    });

    test('masks the 10-bit predicted field', () {
      final reading = G7GlucoseCodec.parseEgv(
        egvPacket(predictedField: 0xFC00 | 200),
      )!;
      expect(reading.predictedMgDl, 200);
    });

    test('out-of-range glucose yields null mgdl but a non-null reading', () {
      final low = G7GlucoseCodec.parseEgv(egvPacket(mgdlField: 30))!;
      expect(low.glucoseMgDl, isNull);
      expect(low.isValid, isFalse);
      final high = G7GlucoseCodec.parseEgv(egvPacket(mgdlField: 600))!;
      expect(high.glucoseMgDl, isNull);
    });

    test('accepts the inclusive 39..501 range bounds', () {
      expect(
        G7GlucoseCodec.parseEgv(egvPacket(mgdlField: 39))!.glucoseMgDl,
        39,
      );
      expect(
        G7GlucoseCodec.parseEgv(egvPacket(mgdlField: 501))!.glucoseMgDl,
        501,
      );
    });

    test('negative trend decodes as a signed value', () {
      final reading = G7GlucoseCodec.parseEgv(egvPacket(trend: -15))!;
      expect(reading.trendTenths, -15);
      expect(reading.trendMgDlPerMin, closeTo(-1.5, 1e-9));
    });

    test('rejects a wrong opcode or a too-short packet', () {
      final wrongOpcode = egvPacket()..[0] = 0x22;
      expect(G7GlucoseCodec.parseEgv(wrongOpcode), isNull);
      expect(G7GlucoseCodec.parseEgv(Uint8List(10)), isNull);
    });
  });

  group('G7GlucoseCodec.parseBackfill', () {
    test('decodes back-to-back records', () {
      final data = Uint8List.fromList([
        ...backfillRecord(secs: 1200, mgdl: 100, type: 0x7, trend: -1),
        ...backfillRecord(secs: 1500, mgdl: 140, type: 0x6),
      ]);
      final records = G7GlucoseCodec.parseBackfill(data);
      expect(records, hasLength(2));
      expect(records[0].secsSinceStart, 1200);
      expect(records[0].glucoseMgDl, 100);
      expect(records[0].trendTenths, -1);
      expect(records[1].secsSinceStart, 1500);
    });

    test('filters records with an invalid type code', () {
      final data = Uint8List.fromList([
        ...backfillRecord(secs: 100, mgdl: 100, type: 0x7),
        ...backfillRecord(secs: 200, mgdl: 120, type: 0x99),
      ]);
      final records = G7GlucoseCodec.parseBackfill(data);
      expect(records, hasLength(1));
      expect(records.single.secsSinceStart, 100);
    });

    test('filters records with out-of-range glucose', () {
      final data = backfillRecord(secs: 100, mgdl: 20, type: 0x7);
      expect(G7GlucoseCodec.parseBackfill(data), isEmpty);
    });

    test('ignores a trailing partial record', () {
      final data = Uint8List.fromList([
        ...backfillRecord(secs: 100, mgdl: 100, type: 0x7),
        0x01, 0x02, 0x03, // 3 stray bytes, < 9
      ]);
      expect(G7GlucoseCodec.parseBackfill(data), hasLength(1));
    });
  });

  group('G7GlucoseReading', () {
    test('timestamp accounts for the reading age', () {
      final reading = G7GlucoseCodec.parseEgv(egvPacket(secs: 3600, age: 30))!;
      final start = DateTime(2024, 1, 1);
      // session start + (secsSinceStart - age) = +3570 s.
      expect(
        reading.timestamp(start),
        start.add(const Duration(seconds: 3570)),
      );
    });

    test('toString summarises a valid reading with a signed trend', () {
      final reading = G7GlucoseCodec.parseEgv(egvPacket(trend: 2, state: 6))!;
      final text = reading.toString();
      expect(text, contains('120 mg/dL'));
      expect(text, contains('+0.2/min'));
      expect(text, contains('state 0x6'));
    });

    test('toString marks an out-of-range reading invalid', () {
      final reading = G7GlucoseCodec.parseEgv(egvPacket(mgdlField: 600))!;
      expect(reading.toString(), startsWith('invalid'));
    });
  });

  group('G7BackfillRecord.toString', () {
    test('renders time, value and hex type', () {
      final record = G7GlucoseCodec.parseBackfill(
        backfillRecord(secs: 1200, mgdl: 100, type: 0xe),
      ).single;
      expect(record.toString(), 'backfill t=1200s 100 mg/dL (type 0xe)');
    });
  });

  group('G7GlucoseCodec.debugDump', () {
    test('hex-dumps each byte zero-padded', () {
      final dump = G7GlucoseCodec.debugDump(Uint8List.fromList([0x0a, 0xff, 0]));
      expect(dump, '0a ff 00');
    });
  });
}
