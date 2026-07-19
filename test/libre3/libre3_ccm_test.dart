import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/libre3/libre3_ccm.dart';
import 'package:insulink/src/libre3/libre3_crypto.dart';
import 'package:insulink/src/libre3/libre3_uuids.dart';

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

  // The encrypt direction (Juggluco's intEncrypt) must match the same standard
  // vector — otherwise an outgoing patch-control command is malformed.
  test('AES-CCM encrypt matches RFC 3610 vector #1', () {
    final key = _hex('C0C1C2C3C4C5C6C7C8C9CACBCCCDCECF');
    final nonce = _hex('00000003020100A0A1A2A3A4A5');
    final aad = _hex('0001020304050607');
    final plaintext = _hex('08090A0B0C0D0E0F101112131415161718191A1B1C1D1E');
    final expected = _hex(
      '588C979A61C663D2F066D0C2C0F989806D5F6B61DAC384'
      '17E8D12CFDF926E0',
    );
    final encrypted = Libre3Ccm.encrypt(
      key: key,
      nonce: nonce,
      plaintext: plaintext,
      aad: aad,
      macBits: 64,
    );
    expect(encrypted, expected);
  });

  // The full Libre-3 command path (Libre3NativeCrypto.encrypt on channel 0) must
  // be the exact inverse of decrypt on the same channel: this exercises the
  // packetDescriptor[0], the sequence-at-tail framing and the nonce ordering
  // ported from Juggluco's intEncrypt/intDecrypt, without any native blob.
  test('control-channel encrypt frame decrypts back to the plaintext', () async {
    final crypto = Libre3NativeCrypto();
    await crypto.initCipher(
      _hex('000102030405060708090A0B0C0D0E0F'), // kEnc
      _hex('1011121314151617'), // ivEnc (8 B)
    );
    final command = _hex('01000105000000'); // ControlHistory from=5
    final frame = await crypto.encrypt(Libre3Uuids.encryptControl, command);
    // ciphertext ‖ tag(4) ‖ sequence(2): 7 + 4 + 2 = 13 bytes, seq starts at 1.
    expect(frame.length, command.length + 6);
    expect(frame.sublist(frame.length - 2), _hex('0100'));
    final back = await crypto.decrypt(Libre3Uuids.encryptControl, frame);
    expect(back, command);
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
