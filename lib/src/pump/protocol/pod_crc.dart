import 'dart:typed_data';

/// CRC-16 over a pod command body, appended to every command the pod accepts.
///
/// The table is the standard CRC-16/IBM one (polynomial 0x8005, MSB-first), but
/// the pod's update loop indexes it by the LOW byte of the running value
/// instead of the high one. That mix is not a textbook CRC, so the loop is
/// reproduced exactly as the pod expects it rather than replaced by a stock
/// implementation. Verified against the captured command vectors in
/// `test/pump/pod_command_test.dart`.
class PodCrc16 {
  PodCrc16(this.bytes);

  final List<int> bytes;

  static final Uint16List _table = _buildTable();

  static Uint16List _buildTable() {
    final table = Uint16List(256);
    for (var index = 0; index < 256; index++) {
      var register = index << 8;
      for (var bit = 0; bit < 8; bit++) {
        final overflow = register & 0x8000 != 0;
        register = (register << 1) & 0xFFFF;
        if (overflow) {
          register ^= 0x8005;
        }
      }
      table[index] = register;
    }
    return table;
  }

  /// The 16-bit checksum, big-endian when appended to a command.
  int get value {
    var register = 0;
    for (final byte in bytes) {
      final index = (byte ^ (register & 0xFF)) & 0xFF;
      register = ((register >> 8) & 0xFF) ^ _table[index];
    }
    return register & 0xFFFF;
  }
}

/// The plain additive checksum the insulin-program commands carry, distinct
/// from [PodCrc16]: a 16-bit sum of the unsigned bytes, wrapping on overflow.
class PodAdditiveChecksum {
  PodAdditiveChecksum(this.bytes);

  final List<int> bytes;

  int get value {
    var sum = 0;
    for (final byte in bytes) {
      sum += byte & 0xFF;
    }
    return sum & 0xFFFF;
  }
}

/// CRC-32 (the zlib/IEEE variant) over a reassembled BLE payload. The pod puts
/// it in the first and last fragment so a dropped middle fragment is caught
/// before the payload is parsed as a command.
class PodCrc32 {
  PodCrc32(this.bytes);

  final List<int> bytes;

  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
    final table = Uint32List(256);
    for (var index = 0; index < 256; index++) {
      var register = index;
      for (var bit = 0; bit < 8; bit++) {
        register = register & 1 != 0
            ? (register >> 1) ^ 0xEDB88320
            : register >> 1;
      }
      table[index] = register;
    }
    return table;
  }

  int get value {
    var register = 0xFFFFFFFF;
    for (final byte in bytes) {
      register = (register >> 8) ^ _table[(register ^ byte) & 0xFF];
    }
    return (register ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
