import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/libre3/libre3_activation.dart';

void main() {
  group('Libre3Activation pure protocol logic', () {
    test('crc16Activation matches Juggluco dp_activation static-asserts', () {
      // Vectors baked into Juggluco's dp_activation.hpp static_asserts.
      int crc(List<int> bytes) =>
          Libre3Activation.crc16Activation(Uint8List.fromList(bytes));
      expect(crc([0, 0, 0, 0, 0, 0, 0, 0]), 0x313E);
      expect(crc([1, 0, 0, 0, 0, 0, 0, 0]), 0xCCBF);
      expect(crc([8, 0, 0, 0, 12, 0, 0, 0]), 0x2063);
    });

    test('manufacturerFromUid reads UID byte 6 (E0 last on Android)', () {
      // Real Libre 3 UID as flutter_nfc_kit reports it (LSB first, E0 last).
      expect(Libre3Activation.manufacturerFromUid('316B978E8E007AE0'), 0x7A);
      // Not an 8-byte E0-terminated UID → null (caller keeps the fallback).
      expect(Libre3Activation.manufacturerFromUid('0007'), isNull);
      expect(Libre3Activation.manufacturerFromUid('316B978E8E007A11'), isNull);
    });

    test('buildActivationParameters lays out time-1 ‖ account ‖ crc', () {
      final params = Libre3Activation.buildActivationParameters(
        activationTimeSec: 1700000000,
        account: 0x1F416D8D,
      );
      // 4 (time-1) + 4 (account) + 2 (crc) = 10 bytes.
      expect(params.length, 10);
      final time =
          params[0] | (params[1] << 8) | (params[2] << 16) | (params[3] << 24);
      expect(time, 1700000000 - 1);
      final account =
          params[4] | (params[5] << 8) | (params[6] << 16) | (params[7] << 24);
      expect(account, 0x1F416D8D);
      final crc = params[8] | (params[9] << 8);
      expect(
        crc,
        Libre3Activation.crc16Activation(Uint8List.sublistView(params, 0, 8)),
      );
    });

    test('parseActivationResponse decodes the real Juggluco nfc2 capture', () {
      // Verbatim from nfc.cpp's documented capture:
      //   00 A500 111DB7193218 9A948F6E 9F0A7562 A2FA
      // → MAC 18:32:19:B7:1D:11, PIN 9A948F6E, A_UTC 1651837599.
      final full = Uint8List.fromList([
        0x00, // zero
        0xA5, 0x00, // response
        0x11, 0x1D, 0xB7, 0x19, 0x32, 0x18, // deviceAddress (reversed on wire)
        0x9A, 0x94, 0x8F, 0x6E, // pin
        0x9F, 0x0A, 0x75, 0x62, // activationTime LE = 1651837599
        0xA2, 0xFA, // crc16 (not verified)
      ]);
      final result = Libre3Activation.parseActivationResponse(full);
      expect(result.bleMac, '18:32:19:B7:1D:11');
      expect(result.blePin, Uint8List.fromList([0x9A, 0x94, 0x8F, 0x6E]));
      expect(result.activationTimeSec, 1651837599);
    });

    test('parseActivationResponse reports a 4-byte app-error reply', () {
      // nfc2error: 00 A5 01 <code>.
      final full = Uint8List.fromList([0x00, 0xA5, 0x01, 0xB0]);
      expect(
        () => Libre3Activation.parseActivationResponse(full),
        throwsStateError,
      );
    });
  });
}
