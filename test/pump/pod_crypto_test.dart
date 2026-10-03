import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/message_packet.dart';
import 'package:insulink/src/pump/protocol/milenage.dart';
import 'package:insulink/src/pump/protocol/session_cipher.dart';

import 'vendor_keys_fixture.dart';

Uint8List hex(String text) {
  final clean = text.replaceAll(',', '').replaceAll(' ', '');
  return Uint8List.fromList([
    for (var index = 0; index < clean.length; index += 2)
      int.parse(clean.substring(index, index + 2), radix: 16),
  ]);
}

String toHex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('Milenage', skip: installOmnipodVendorKeys(), () {
    test('derives RES, CK and AUTN for a captured session', () {
      final milenage = Milenage(
        key: hex('c0772899720972a314f557de66d571dd'),
        sqn: hex('000000000002'),
        rand: hex('c2cd1248451103bd77a6c7ef88c441ba'),
      );
      expect(toHex(milenage.res), 'a40bc6d13861447e');
      expect(toHex(milenage.ck), '55799fd26664cbf6e476525e2dee52c6');
      expect(toHex(milenage.autn), '00c55c78e8d3b9b9e935860a7259f6c0');
    });

    test('derives a second captured session', () {
      final milenage = Milenage(
        key: hex('78411ccad0fd0fb6f381a47fb3335ecb'),
        sqn: hex('000000000002'),
        rand: hex('4fc01ac1a94376ae3e052339c07d9e1f'),
      );
      expect(toHex(milenage.res), 'ec549e00fa668a19');
      expect(toHex(milenage.ck), 'ee3dac761fe358a9f476cc5ee81aa3e9');
      expect(toHex(milenage.autn), 'a3e7a71430c8b9b95245b33b3bd679c4');
    });

    test('tracks an incremented sequence number', () {
      final milenage = Milenage(
        key: hex('c0772899720972a314f557de66d571dd'),
        sqn: hex('00000000015e'),
        rand: hex('d71cc44820e5419f42c62ae97c035988'),
      );
      expect(toHex(milenage.res), '5f807a379a5c5d30');
      expect(toHex(milenage.ck), '8dd4b3ceb849a01766e37f9d86045c39');
      expect(toHex(milenage.autn), '0e0264d056fcb9b9752227365a090955');
    });

    test('recovers the pod sequence number on a resynchronisation', () {
      final milenage = Milenage(
        key: hex('689b860fde3331dd7e1671ad39985e3b'),
        sqn: hex('000000000008'),
        rand: hex('396707041ca3a5931fc0e52d2d7b9ecf'),
        auts: hex('84ff173947a67567985de71e4890'),
        amf: Uint8List.fromList(Milenage.resyncAmf),
      );
      expect(toHex(milenage.receivedMacS), toHex(milenage.macS));
      expect(toHex(milenage.synchronizationSqn), toHex(milenage.sqn));
    });
  });

  group('SessionCipher', () {
    test('decrypts a captured pod response', () {
      final received = hex(
        '54,57,11,a1,0c,16,03,00,08,20,2e,a9,08,20,2e,a8,34,7c,b9,7b,38,5d,45,'
        'a3,c4,0e,40,4c,55,71,5e,f3,c3,86,50,17,36,7e,62,3c,7d,0b,46,9e,81,cd,fd,9a',
      );
      final cipher = SessionCipher(
        nonce: SessionNonce(prefix: hex('6cff5d18b7616cae'), sequence: 22),
        confidentialityKey: hex('55799fd26664cbf6e476525e2dee52c6'),
      );
      final plain = cipher.decrypt(MessagePacket.parse(received));
      expect(toHex(plain.payload),
          '302e303d0012 08202ea9 1c0a1d05 0016b000 0000 0bff01fe'.replaceAll(' ', ''));
    });

    test('encrypts a captured controller command to the same bytes', () {
      final expected = hex(
        '54571101070003400242000002420001'
        'e09158bcb0285a81bf30635f3a17ee73f0afbb3286bc524a8a66fb1bc5b001e56543',
      );
      final cipher = SessionCipher(
        nonce: SessionNonce(prefix: hex('dda23c090a0a0a0a'), sequence: 0),
        confidentialityKey: hex('ba1283744b6de9fab6d9b77d95a71d6e'),
      );
      final command = hex('53302e303d000effffffff00060704ffffffff82b22c47302e30');
      final message = MessagePacket.parse(expected).withPayload(command);
      expect(toHex(cipher.encrypt(message).toBytes()), toHex(expected));
    });

    test('a tampered tag is refused rather than returning garbage', () {
      final received = hex(
        '54,57,11,a1,0c,16,03,00,08,20,2e,a9,08,20,2e,a8,34,7c,b9,7b,38,5d,45,'
        'a3,c4,0e,40,4c,55,71,5e,f3,c3,86,50,17,36,7e,62,3c,7d,0b,46,9e,81,cd,fd,9b',
      );
      final cipher = SessionCipher(
        nonce: SessionNonce(prefix: hex('6cff5d18b7616cae'), sequence: 22),
        confidentialityKey: hex('55799fd26664cbf6e476525e2dee52c6'),
      );
      expect(() => cipher.decrypt(MessagePacket.parse(received)),
          throwsA(isA<PodDecryptException>()));
    });

    test('the direction bit keeps the two sides off each other nonces', () {
      final nonce = SessionNonce(prefix: hex('0000000000000000'), sequence: 5);
      final toPod = nonce.next(podIsReceiver: true);
      nonce.sequence = 5;
      final fromPod = nonce.next(podIsReceiver: false);
      expect(toPod[8] & 0x80, 0);
      expect(fromPod[8] & 0x80, 0x80);
    });
  });
}
