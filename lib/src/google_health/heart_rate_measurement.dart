import 'package:flutter/foundation.dart';

/// A parsed SIG Heart Rate Measurement (characteristic 0x2A37).
@immutable
class HeartRateMeasurement {
  const HeartRateMeasurement(this.bpm, this.rrIntervalsMs);

  final int bpm;
  final List<int> rrIntervalsMs;

  /// Decodes the SIG Heart Rate Measurement value, or null if malformed.
  /// flags bit0: 0 => 8-bit bpm, 1 => 16-bit bpm. bit3: energy-expended field
  /// present (2 bytes, skipped). bit4: RR-interval fields present (each 1/1024 s).
  static HeartRateMeasurement? parse(List<int> data) {
    if (data.isEmpty) {
      return null;
    }
    final flags = data[0];
    var offset = 1;
    final int bpm;
    if (flags & 0x01 != 0) {
      if (data.length < 3) {
        return null;
      }
      bpm = data[1] | (data[2] << 8);
      offset = 3;
    } else {
      if (data.length < 2) {
        return null;
      }
      bpm = data[1];
      offset = 2;
    }
    if (flags & 0x08 != 0) {
      offset += 2;
    }
    final rrIntervalsMs = <int>[];
    if (flags & 0x10 != 0) {
      while (offset + 1 < data.length) {
        final raw = data[offset] | (data[offset + 1] << 8);
        rrIntervalsMs.add((raw / 1024 * 1000).round());
        offset += 2;
      }
    }
    return HeartRateMeasurement(bpm, rrIntervalsMs);
  }
}
