import 'dart:typed_data';

import '../cgm/cgm_connection.dart';

/// Decoders for the FreeStyle Libre 3 BLE glucose payloads, producing the shared
/// [CgmReading] so the rest of the pipeline is identical to the G7.
///
/// Byte layouts ported verbatim from DiaBLE's `Libre3.parseOneMinuteReading`
/// (see docs/LIBRE3.md). Glucose is already mg/dL — masked to the low 13 bits,
/// with bit 15 the sensor's error flag. The "life count" is minutes since
/// activation, so the session clock is `lifeCount * 60` seconds.
class Libre3GlucoseCodec {
  static const _errorFlag = 0x8000;
  static const _glucoseMask = 0x1FFF;

  /// Int16 sentinel Abbott uses for "no rate of change".
  static const _rateUnset = -32768;

  static bool _validMgdl(int mgdl) => mgdl >= 39 && mgdl <= 501;

  /// Parse the 29-byte One-Minute Reading (characteristic `0898177A`).
  static CgmReading? parseOneMinuteReading(Uint8List data) {
    if (data.length < 21) {
      return null;
    }
    final bytes = ByteData.sublistView(data);
    final lifeCount = bytes.getUint16(0, Endian.little);
    final rawGlucose = bytes.getUint16(2, Endian.little);
    final hasError = (rawGlucose & _errorFlag) != 0;
    final glucose = rawGlucose & _glucoseMask;
    final rate = bytes.getInt16(4, Endian.little);
    final projected = bytes.getUint16(8, Endian.little) ~/ 100;
    final bitfields = data[14];
    return CgmReading(
      secsSinceStart: lifeCount * 60,
      age: 0,
      sequence: lifeCount,
      glucoseMgDl: (!hasError && _validMgdl(glucose)) ? glucose : null,
      predictedMgDl: projected,
      trendTenths: rate == _rateUnset ? 0 : (rate / 10).round(),
      // Keep the raw trend/status bitfield as the sensor state byte.
      state: bitfields,
      raw: data,
    );
  }

  /// A single historical (backfill) record — 5-minute cadence.
  ///
  /// The 20-byte historical packet (`0898195A`) is a start life count followed
  /// by up to six back-to-back 2-byte glucose values at decreasing 5-minute
  /// offsets. ponytail: the record stride is the one field to confirm on-device
  /// against a real backfill capture; the glucose masking is certain.
  static List<Libre3HistoricalRecord> parseHistorical(Uint8List data) {
    if (data.length < 4) {
      return const [];
    }
    final bytes = ByteData.sublistView(data);
    final startLifeCount = bytes.getUint16(0, Endian.little);
    final out = <Libre3HistoricalRecord>[];
    var offset = 2;
    var index = 0;
    while (offset + 2 <= data.length) {
      final raw = bytes.getUint16(offset, Endian.little);
      final glucose = raw & _glucoseMask;
      if ((raw & _errorFlag) == 0 && _validMgdl(glucose)) {
        out.add(
          Libre3HistoricalRecord(
            secsSinceStart: (startLifeCount - index * 5) * 60,
            glucoseMgDl: glucose,
          ),
        );
      }
      offset += 2;
      index++;
    }
    return out;
  }
}

/// One decoded historical Libre 3 point (backfill), keyed by seconds since the
/// sensor session started so it merges with the shared history the same way a
/// G7 backfill record does.
class Libre3HistoricalRecord {
  Libre3HistoricalRecord({
    required this.secsSinceStart,
    required this.glucoseMgDl,
  });

  final int secsSinceStart;
  final int glucoseMgDl;
}
