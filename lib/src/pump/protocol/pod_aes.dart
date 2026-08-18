import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// The AES primitives the pod protocol needs, in one place so the key material
/// only ever passes through code that is covered by the known-answer tests.
class PodAes {
  PodAes(this.key) : assert(key.length == 16);

  final Uint8List key;

  /// One raw AES-128 block, no mode and no padding. Milenage is defined in
  /// terms of single-block encryptions, not a stream.
  Uint8List encryptBlock(Uint8List block) {
    assert(block.length == 16);
    final engine = AESEngine()..init(true, KeyParameter(key));
    final out = Uint8List(16);
    engine.processBlock(block, 0, out, 0);
    return out;
  }

  /// AES-CMAC (RFC 4493), the MAC the pairing key ladder is built from.
  Uint8List cmac(Uint8List data) {
    final mac = CMac(AESEngine(), 128)..init(KeyParameter(key));
    return mac.process(data);
  }
}

/// Byte-wise XOR of two equally long buffers.
Uint8List xorBytes(Uint8List left, Uint8List right) {
  assert(left.length == right.length);
  final out = Uint8List(left.length);
  for (var index = 0; index < left.length; index++) {
    out[index] = left[index] ^ right[index];
  }
  return out;
}
