import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/message_packet.dart';
import 'package:insulink/src/pump/protocol/payload_fragments.dart';
import 'package:insulink/src/pump/protocol/payload_reassembler.dart';
import 'package:insulink/src/pump/protocol/pod_crc.dart';
import 'package:insulink/src/pump/protocol/pod_ids.dart';

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
  group('CRC', () {
    test('crc16 matches captured command trailers', () {
      expect(PodCrc16(hex('FFFFFFFF00060704FFFFFFFF')).value, 0x82B2);
      expect(PodCrc16(hex('0242000114061C04494E532E')).value, 0x001C);
      expect(PodCrc16(hex('024200023C030E0100')).value, 0x024C);
    });

    test('crc32 matches the IEEE reference value', () {
      expect(PodCrc32(Uint8List.fromList('123456789'.codeUnits)).value, 0xCBF43926);
    });
  });

  group('MessagePacket', () {
    final captured = hex(
      '54,57,11,01,07,00,03,40,08,20,2e,a8,08,20,2e,a9,ab,35,d8,31,60,9b,b8,fe,'
      '3a,3b,de,5b,18,37,24,9a,16,db,f8,e4,d3,05,e9,75,dc,81,7c,37,07,cc,41,5f,af,8a',
    );

    test('parses a captured encrypted packet', () {
      final packet = MessagePacket.parse(captured);
      expect(packet.type, PodMessageType.encrypted);
      expect(packet.source, PodId.fromInt(136326824));
      expect(packet.destination, PodId.fromInt(136326825));
      expect(packet.sequenceNumber, 7);
      expect(packet.ackNumber, 0);
      expect(packet.eqos, 1);
      expect(packet.sas, isTrue);
      expect(packet.tfs, isFalse);
      expect(packet.priority, isFalse);
      expect(packet.version, 0);
      expect(toHex(packet.payload), toHex(captured.sublist(16)));
    });

    test('re-serializes to the same bytes', () {
      expect(toHex(MessagePacket.parse(captured).toBytes()), toHex(captured));
    });

    test('rejects a frame without the TW magic', () {
      final broken = Uint8List.fromList(captured)..[0] = 0x55;
      expect(() => MessagePacket.parse(broken), throwsA(isA<PodMessageException>()));
    });

    test('rejects a truncated frame rather than reading past its end', () {
      expect(() => MessagePacket.parse(captured.sublist(0, 20)),
          throwsA(isA<PodMessageException>()));
    });
  });

  group('BLE fragmentation', () {
    Uint8List body(int length) =>
        Uint8List.fromList(List<int>.generate(length, (index) => (index * 7 + 3) & 0xFF));

    Uint8List roundTrip(Uint8List payload) {
      final fragments = PodFragmenter(payload).fragments;
      final joiner = PodReassembler(fragments.first);
      for (final fragment in fragments.skip(1)) {
        joiner.accumulate(fragment);
      }
      expect(joiner.isComplete, isTrue);
      return joiner.finish();
    }

    test('round-trips every length across the fragment boundaries', () {
      for (var length = 1; length <= 250; length++) {
        final payload = body(length);
        expect(toHex(roundTrip(payload)), toHex(payload), reason: 'length $length');
      }
    });

    test('every fragment fits one BLE write', () {
      for (final fragment in PodFragmenter(body(200)).fragments) {
        expect(fragment.length, PodFragmentSizes.frame);
      }
    });

    test('a dropped middle fragment is refused, not silently joined', () {
      final fragments = PodFragmenter(body(120)).fragments;
      final joiner = PodReassembler(fragments.first);
      joiner.accumulate(fragments[1]);
      expect(() => joiner.accumulate(fragments[3]),
          throwsA(isA<PodFragmentException>()));
    });

    test('a corrupted byte is caught by the CRC', () {
      final fragments = PodFragmenter(body(120)).fragments;
      fragments[1][5] ^= 0xFF;
      final joiner = PodReassembler(fragments.first);
      for (final fragment in fragments.skip(1)) {
        joiner.accumulate(fragment);
      }
      expect(joiner.finish, throwsA(isA<PodFragmentException>()));
    });
  });
}
