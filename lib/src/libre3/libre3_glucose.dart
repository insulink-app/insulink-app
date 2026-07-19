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
    final temperature = data.length >= 21
        ? bytes.getUint16(19, Endian.little)
        : null;
    return CgmReading(
      secsSinceStart: lifeCount * 60,
      age: 0,
      sequence: lifeCount,
      glucoseMgDl: (!hasError && _validMgdl(glucose)) ? glucose : null,
      predictedMgDl: projected,
      trendTenths: rate == _rateUnset ? 0 : (rate / 10).round(),
      // Keep the raw trend/status bitfield as the sensor state byte.
      state: bitfields,
      temperatureCentiC: temperature,
      raw: data,
    );
  }

  /// The historical (backfill) records in one decrypted packet — 5-minute
  /// cadence (`historic` char, decrypt channel 4). Ported from Juggluco's
  /// `HistoryData`: a `uint16` start life count followed by `(len/2) − 1`
  /// back-to-back `uint16` glucose values, each **+5 min** after the last
  /// (ascending). Plain `uint16` mg/dL (no 13-bit mask / error flag), validated
  /// by range.
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
      final glucose = bytes.getUint16(offset, Endian.little);
      if (_validMgdl(glucose)) {
        out.add(
          Libre3HistoricalRecord(
            secsSinceStart: (startLifeCount + index * 5) * 60,
            glucoseMgDl: glucose,
          ),
        );
      }
      offset += 2;
      index++;
    }
    return out;
  }

  /// Clinical/"fast" records (`clinicalData` char, decrypt channel 5) — the
  /// sensor's 2-hour, minute-by-minute buffer, one record per notification at
  /// 1-min cadence.
  ///
  /// Unlike historic, each [_clinicalRecordLen]-byte record is a struct, NOT a
  /// run of glucose values. Confirmed on-device: `lifeCount` at `[0..2)` and the
  /// calibrated glucose `uint16` at `[10..12)` (the [10..12) column tracked the
  /// live reading exactly; the intervening fields are raw/unsmoothed values we
  /// don't need). Parsed in fixed-size strides so a multi-record packet still
  /// decodes.
  static const _clinicalRecordLen = 14;
  static const _clinicalGlucoseOffset = 10;

  static List<Libre3HistoricalRecord> parseClinical(Uint8List data) {
    final bytes = ByteData.sublistView(data);
    final out = <Libre3HistoricalRecord>[];
    var base = 0;
    while (base + _clinicalRecordLen <= data.length) {
      final lifeCount = bytes.getUint16(base, Endian.little);
      final glucose = bytes.getUint16(
        base + _clinicalGlucoseOffset,
        Endian.little,
      );
      if (_validMgdl(glucose)) {
        out.add(
          Libre3HistoricalRecord(
            secsSinceStart: lifeCount * 60,
            glucoseMgDl: glucose,
          ),
        );
      }
      base += _clinicalRecordLen;
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
