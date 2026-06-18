import 'dart:typed_data';

/// A decoded estimated glucose value (EGV) from the G7.
///
/// Layout confirmed against real sensor packets and Juggluco's `glucoseinput`
/// struct (java.cpp) — packed, little-endian:
///   [0]      uint8   type (0x4E for a live EGV)
///   [1]      int8    status
///   [2..6)   int32   secsSinceStart (seconds since sensor session start)
///   [6..8)   uint16  sequence
///   [8..10)  uint16  (reserved)
///   [10..12) uint16  age (seconds since this reading was taken)
///   [12..14) uint16  mgdL:12 | donly:4      → glucose = value & 0x0FFF
///   [14]     int8    state (algorithm/calibration state)
///   [15]     int8    trend (0.1 mg/dL per minute)
///   [16..18) uint16  predictedmgdL:10 | unknown:6 → predicted = value & 0x03FF
///   [18]     uint8   info
class G7GlucoseReading {
  G7GlucoseReading({
    required this.secsSinceStart,
    required this.age,
    required this.sequence,
    required this.glucoseMgDl,
    required this.predictedMgDl,
    required this.trendTenths,
    required this.state,
    this.raw,
  });

  final int secsSinceStart;
  final int age;
  final int sequence;

  /// Glucose in mg/dL, or null if out of the valid 39..501 range.
  final int? glucoseMgDl;
  final int predictedMgDl;

  /// Trend in 0.1 mg/dL per minute (so 2 == +0.2 mg/dL/min).
  final int trendTenths;
  final int state;
  final Uint8List? raw;

  double get trendMgDlPerMin => trendTenths / 10.0;
  bool get isValid => glucoseMgDl != null;

  /// Wall-clock time of this reading, given the sensor session start.
  DateTime timestamp(DateTime sessionStart) =>
      sessionStart.add(Duration(seconds: secsSinceStart - age));

  @override
  String toString() => isValid
      ? '$glucoseMgDl mg/dL (${trendMgDlPerMin >= 0 ? '+' : ''}'
            '${trendMgDlPerMin.toStringAsFixed(1)}/min), predicted $predictedMgDl, '
            'age ${age}s, state 0x${state.toRadixString(16)}'
      : 'invalid (state 0x${state.toRadixString(16)}, age ${age}s)';
}

/// A single historical record from the backfill stream (Juggluco `dexbackfill`,
/// 9 bytes, little-endian): int32 secsSinceStart, int16 mgdL, uint8 type,
/// uint8 extra, int8 trend.
class G7BackfillRecord {
  G7BackfillRecord({
    required this.secsSinceStart,
    required this.glucoseMgDl,
    required this.type,
    required this.trendTenths,
  });

  final int secsSinceStart;
  final int glucoseMgDl;
  final int type;
  final int trendTenths;

  /// Backfill records are valid only for these type codes.
  bool get isValid => type == 0x6 || type == 0x7 || type == 0xe;

  @override
  String toString() =>
      'backfill t=${secsSinceStart}s $glucoseMgDl mg/dL (type 0x${type.toRadixString(16)})';
}

class G7GlucoseCodec {
  static bool _validMgdl(int v) => v >= 39 && v <= 501;

  /// Parse a live EGV packet (Control characteristic, opcode 0x4E).
  static G7GlucoseReading? parseEgv(Uint8List p) {
    if (p.length < 19 || p[0] != 0x4E) return null;
    final bd = ByteData.sublistView(p);
    final secs = bd.getInt32(2, Endian.little);
    final sequence = bd.getUint16(6, Endian.little);
    final age = bd.getUint16(10, Endian.little);
    final mgdl = bd.getUint16(12, Endian.little) & 0x0FFF;
    final state = bd.getInt8(14);
    final trend = bd.getInt8(15);
    final predicted = bd.getUint16(16, Endian.little) & 0x03FF;
    return G7GlucoseReading(
      secsSinceStart: secs,
      age: age,
      sequence: sequence,
      glucoseMgDl: _validMgdl(mgdl) ? mgdl : null,
      predictedMgDl: predicted,
      trendTenths: trend,
      state: state,
      raw: p,
    );
  }

  /// Backfill characteristic delivers fixed 9-byte records back-to-back.
  static List<G7BackfillRecord> parseBackfill(Uint8List data) {
    const w = 9;
    final out = <G7BackfillRecord>[];
    for (var off = 0; off + w <= data.length; off += w) {
      final bd = ByteData.sublistView(data, off, off + w);
      final rec = G7BackfillRecord(
        secsSinceStart: bd.getInt32(0, Endian.little),
        glucoseMgDl: bd.getInt16(4, Endian.little),
        type: bd.getUint8(6),
        trendTenths: bd.getInt8(8),
      );
      if (rec.isValid && _validMgdl(rec.glucoseMgDl)) out.add(rec);
    }
    return out;
  }

  static String debugDump(Uint8List p) =>
      p.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
