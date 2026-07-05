import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/libre3/libre3_activation.dart';

void main() {
  group('Libre3Activation pure protocol logic', () {
    test('fnv32 is deterministic and 32-bit', () {
      final hash = Libre3Activation.fnv32('abc');
      expect(hash, Libre3Activation.fnv32('abc'));
      expect(hash, inInclusiveRange(0, 0xFFFFFFFF));
      // Distinct inputs hash differently.
      expect(hash, isNot(Libre3Activation.fnv32('abd')));
    });

    test('fnv32 matches the DiaBLE reduction by hand', () {
      // acc starts 0; per char acc = ((acc*prime)&0xFFFFFFFF) ^ ascii.
      var expected = 0;
      for (final unit in 'A1'.codeUnits) {
        expected = ((expected * 0x811C9DC5) & 0xFFFFFFFF) ^ unit;
      }
      expect(Libre3Activation.fnv32('A1'), expected);
    });

    test('crc16 is stable and order-sensitive', () {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      expect(Libre3Activation.crc16(data), Libre3Activation.crc16(data));
      expect(
        Libre3Activation.crc16(data),
        isNot(Libre3Activation.crc16(Uint8List.fromList([4, 3, 2, 1]))),
      );
    });

    test('a built parameter block carries a self-consistent CRC', () {
      final params = Libre3Activation.buildActivationParameters(
        activationTimeSec: 1700000000,
        accountId: 'test-account',
      );
      // 4 (time) + 4 (receiverId) + 2 (crc) = 10 bytes.
      expect(params.length, 10);
      final body = Uint8List.sublistView(params, 0, 8);
      final crc = params[8] | (params[9] << 8);
      expect(crc, Libre3Activation.crc16(body));
    });

    test('parseActivationResponse decodes MAC / PIN / time and checks CRC', () {
      // Build a synthetic 16-byte body: MAC(6, reversed on the wire) ‖ PIN(4) ‖
      // time LE32(4) ‖ crc LE16(2), then prefix filler + flag as the sensor does.
      final body = BytesBuilder();
      body.add([0xAB, 0x89, 0x67, 0x45, 0x23, 0xC1]); // wire order (reversed MAC)
      body.add([0xDE, 0xAD, 0xBE, 0xEF]); // PIN
      body.add([0x00, 0x9A, 0xCD, 0x65]); // time LE32 = 0x65CD9A00
      final head = body.toBytes();
      final crc = Libre3Activation.crc16(head);
      final full = Uint8List.fromList([
        0xA5, 0xA5, // leading filler
        0x00, // flag = OK
        ...head,
        crc & 0xFF, (crc >> 8) & 0xFF,
      ]);

      final result = Libre3Activation.parseActivationResponse(full);
      expect(result.bleMac, 'C1:23:45:67:89:AB');
      expect(result.blePin, Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]));
      expect(result.activationTimeSec, 0x65CD9A00);
    });

    test('parseActivationResponse rejects a corrupted CRC', () {
      final body = List<int>.filled(14, 0x11);
      final full = Uint8List.fromList([0x00, ...body, 0x00, 0x00]);
      expect(
        () => Libre3Activation.parseActivationResponse(full),
        throwsStateError,
      );
    });
  });
}
