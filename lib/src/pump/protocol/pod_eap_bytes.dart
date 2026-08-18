import 'dart:typed_data';

/// The EAP sequence number is a 48-bit big-endian counter on the wire.
Uint8List encodeEapSequence(int value) {
  final out = Uint8List(6);
  var remaining = value;
  for (var index = 5; index >= 0; index--) {
    out[index] = remaining & 0xFF;
    remaining >>= 8;
  }
  return out;
}

int decodeEapSequence(Uint8List value) {
  var out = 0;
  for (final byte in value) {
    out = (out << 8) | byte;
  }
  return out;
}

/// Compares two buffers without leaking where they first differ.
///
/// Used on the challenge response and the resynchronisation signature: both
/// decide whether we are talking to the pod we paired with, so an early return
/// on the first mismatching byte would be a timing side channel on key material.
bool constantTimeEquals(Uint8List left, Uint8List right) {
  if (left.length != right.length) {
    return false;
  }
  var mismatch = 0;
  for (var index = 0; index < left.length; index++) {
    mismatch |= left[index] ^ right[index];
  }
  return mismatch == 0;
}
