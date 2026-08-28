import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_eap.dart';

Uint8List hex(String text) => Uint8List.fromList([
      for (var index = 0; index < text.length; index += 2)
        int.parse(text.substring(index, index + 2), radix: 16),
    ]);

String toHex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // A captured AKA challenge: AUTN, RAND and the controller's nonce half.
  final challenge = hex('01bd0038170100000205000000c55c78e8d3b9b9e935860a7259f6c0'
      '01050000c2cd1248451103bd77a6c7ef88c441ba7e0200006cff5d18');

  test('parses a captured AKA challenge and re-serializes it byte for byte', () {
    final message = PodEapMessage.parse(challenge);
    expect(message.code, PodEapCode.request);
    expect(message.identifier, 0xbd);
    expect(message.subType, PodEapMessage.subTypeChallenge);
    expect(message.attributes.map((attribute) => attribute.type), [
      PodEapAttributeType.autn,
      PodEapAttributeType.rand,
      PodEapAttributeType.customIv,
    ]);
    expect(toHex(message.toBytes()), toHex(challenge));
  });

  test('reads the attribute payloads', () {
    final message = PodEapMessage.parse(challenge);
    expect(toHex(message.attributes[0].payload),
        '00c55c78e8d3b9b9e935860a7259f6c0');
    expect(toHex(message.attributes[1].payload),
        'c2cd1248451103bd77a6c7ef88c441ba');
    expect(toHex(message.attributes[2].payload), '6cff5d18');
  });

  test('a bare success message is four bytes', () {
    const message = PodEapMessage(code: PodEapCode.success, identifier: 0xbd);
    expect(toHex(message.toBytes()), '03bd0004');
    final parsed = PodEapMessage.parse(hex('03bd0004'));
    expect(parsed.code, PodEapCode.success);
    expect(parsed.attributes, isEmpty);
  });

  test('a response carrying RES round-trips', () {
    final res = PodEapAttribute(
        PodEapAttributeType.res, hex('a40bc6d13861447e'));
    expect(toHex(res.encoded), '03030040a40bc6d13861447e');
    final rebuilt = PodEapMessage.parse(Uint8List.fromList([
      2, 0xbd, 0, 20, 0x17, 1, 0, 0, ...res.encoded,
    ]));
    expect(rebuilt.attributes.single.type, PodEapAttributeType.res);
    expect(toHex(rebuilt.attributes.single.payload), 'a40bc6d13861447e');
  });

  test('parses a synchronisation failure carrying AUTS', () {
    final auts = hex('84ff173947a67567985de71e4890');
    final message = PodEapMessage.parse(Uint8List.fromList([
      1, 0xbd, 0, 24, 0x17, PodEapMessage.subTypeSynchronizationFailure, 0, 0,
      4, 4, ...auts,
    ]));
    expect(message.subType, PodEapMessage.subTypeSynchronizationFailure);
    expect(message.attributes.single.type, PodEapAttributeType.auts);
    expect(toHex(message.attributes.single.payload), toHex(auts));
  });

  test('rejects a non-AKA packet type', () {
    expect(() => PodEapMessage.parse(hex('01bd0008160100000000')),
        throwsA(isA<PodEapException>()));
  });

  test('rejects an attribute that declares more than it carries', () {
    expect(
      () => PodEapMessage.parse(
          Uint8List.fromList([1, 0xbd, 0, 12, 0x17, 1, 0, 0, 1, 5, 0, 0])),
      throwsA(isA<PodEapException>()),
    );
  });

  test('rejects a truncated message', () {
    expect(() => PodEapMessage.parse(hex('01bd')), throwsA(isA<PodEapException>()));
  });
}
