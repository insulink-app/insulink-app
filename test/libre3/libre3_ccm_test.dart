import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/libre3/libre3_ccm.dart';

Uint8List _hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

void main() {
  // RFC 3610 Test Vector #1 — proves our use of pointycastle's AES-CCM matches
  // the standard (independent of the Libre-specific nonce/AAD wiring).
  test('AES-CCM decrypt matches RFC 3610 vector #1', () {
    final key = _hex('C0C1C2C3C4C5C6C7C8C9CACBCCCDCECF');
    final nonce = _hex('00000003020100A0A1A2A3A4A5');
    final aad = _hex('0001020304050607');
    final plaintext = _hex('08090A0B0C0D0E0F101112131415161718191A1B1C1D1E');
    final ciphertextAndTag = _hex(
      '588C979A61C663D2F066D0C2C0F989806D5F6B61DAC384' // 23-byte ciphertext
      '17E8D12CFDF926E0', // 8-byte tag (M=8 → macBits 64)
    );

    final decrypted = Libre3Ccm.decrypt(
      key: key,
      nonce: nonce,
      ciphertextAndTag: ciphertextAndTag,
      aad: aad,
      macBits: 64,
    );
    expect(decrypted, plaintext);
  });

  test('a tampered tag is rejected', () {
    final key = _hex('C0C1C2C3C4C5C6C7C8C9CACBCCCDCECF');
    final nonce = _hex('00000003020100A0A1A2A3A4A5');
    final aad = _hex('0001020304050607');
    final bad = _hex(
      '588C979A61C663D2F066D0C2C0F989806D5F6B61DAC384'
      '17E8D12CFDF926FF', // last tag byte flipped
    );
    expect(
      () => Libre3Ccm.decrypt(
        key: key,
        nonce: nonce,
        ciphertextAndTag: bad,
        aad: aad,
        macBits: 64,
      ),
      throwsStateError,
    );
  });
}
