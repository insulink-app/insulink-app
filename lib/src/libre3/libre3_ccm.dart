import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// AES-128-CCM for the FreeStyle Libre 3 data path.
///
/// This is the clean-room half of the crypto: once the BLE handshake yields the
/// session key `kEnc` and IV `ivEnc` (via the Abbott blob), every data
/// characteristic is plain AES-128-CCM — Juggluco does it in its OWN code
/// (`initcrypt`/`intDecrypt`), not the blob. We use pointycastle's audited
/// `CCMBlockCipher` rather than rolling our own.
class Libre3Ccm {
  /// One-shot CCM encrypt of `plaintext`, returning `ciphertext ‖ tag`. The
  /// counterpart of [decrypt] (Juggluco's `intEncrypt`), used for the outgoing
  /// patch-control command.
  static Uint8List encrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List plaintext,
    Uint8List? aad,
    int macBits = 32,
  }) {
    final cipher = CCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), macBits, nonce, aad ?? Uint8List(0)),
      );
    return cipher.process(plaintext);
  }

  /// One-shot CCM decrypt of `ciphertext ‖ tag`. Throws
  /// `InvalidCipherTextException` if the tag doesn't verify.
  static Uint8List decrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List ciphertextAndTag,
    Uint8List? aad,
    int macBits = 32,
  }) {
    final cipher = CCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), macBits, nonce, aad ?? Uint8List(0)),
      );
    return cipher.process(ciphertextAndTag);
  }
}
