import 'dart:typed_data';

/// Raised when a keyed payload does not carry the keys it should.
class PodKeyedPayloadException implements Exception {
  PodKeyedPayloadException(this.message);

  final String message;

  @override
  String toString() => 'PodKeyedPayloadException: $message';
}

/// The pod wraps its payloads in short ASCII keys with a big-endian 16-bit
/// length after each one — `SP1=`, `SPS1=`, `S0.0=` and so on. A key whose
/// payload is empty carries no length at all, and the final key may be present
/// with nothing after it.
///
/// Note: the reference implementation decodes the length as `high << 1 | low`,
/// which only happens to work because every real payload here is shorter than
/// 256 bytes. This decodes it as the big-endian value it is written as, which
/// agrees for every payload the pod actually sends and stays correct beyond it.
class PodKeyedPayload {
  const PodKeyedPayload(this.keys);

  final List<String> keys;

  Uint8List encode(List<Uint8List> payloads) {
    if (payloads.length != keys.length) {
      throw PodKeyedPayloadException('Expected ${keys.length} payloads');
    }
    final parts = <int>[];
    for (var index = 0; index < keys.length; index++) {
      parts.addAll(keys[index].codeUnits);
      final payload = payloads[index];
      if (payload.isNotEmpty) {
        parts
          ..add((payload.length >> 8) & 0xFF)
          ..add(payload.length & 0xFF)
          ..addAll(payload);
      }
    }
    return Uint8List.fromList(parts);
  }

  List<Uint8List> decode(Uint8List payload) {
    final out = <Uint8List>[];
    var remaining = payload;
    for (var index = 0; index < keys.length; index++) {
      final key = keys[index];
      if (remaining.length < key.length ||
          String.fromCharCodes(remaining.sublist(0, key.length)) != key) {
        throw PodKeyedPayloadException('Key "$key" not found in payload');
      }
      if (index == keys.length - 1 && remaining.length == key.length) {
        out.add(Uint8List(0));
        return out;
      }
      if (remaining.length < key.length + 2) {
        throw PodKeyedPayloadException('Key "$key" has no length');
      }
      remaining = remaining.sublist(key.length);
      final length = (remaining[0] << 8) | remaining[1];
      if (remaining.length < 2 + length) {
        throw PodKeyedPayloadException('Key "$key" announces $length bytes it does not carry');
      }
      out.add(remaining.sublist(2, 2 + length));
      remaining = remaining.sublist(2 + length);
    }
    return out;
  }
}
