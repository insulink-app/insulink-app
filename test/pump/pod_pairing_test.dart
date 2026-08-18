import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/key_exchange.dart';
import 'package:insulink/src/rust/frb_generated.dart';

Uint8List hex(String text) => Uint8List.fromList([
      for (var index = 0; index < text.length; index += 2)
        int.parse(text.substring(index, index + 2), radix: 16),
    ]);

String toHex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  setUpAll(() async {
    final library = File('rust/target/debug/librust_lib_insulink.so');
    if (!library.existsSync()) {
      throw StateError(
        'Host Rust library missing — run `cd rust && cargo build` before this test.',
      );
    }
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(library.absolute.path),
    );
  });

  group('PodKeyExchange', () {
    // Captured pairing: a known controller key pair and pod offer, with the
    // long-term key and both confirmation values the pod agreed on. Built in
    // setUpAll because the constructor already reaches into the Rust core.
    late PodKeyExchange exchange;

    setUpAll(() {
      exchange = PodKeyExchange(
        privateKey:
            hex('27ec94b71a201c5e92698d668806ae5ba00594c307cf5566e60c1fc53a6f6bb6'),
        controllerNonce: hex('edfdacb242c7f4e1d2bc4d93ca3c5706'),
      );
      exchange.acceptPodOffer(hex(
        '2fe57da347cd62431528daac5fbb290730fff684afc4cfc2ed90995f58cb3b74'
        '00000000000000000000000000000000',
      ));
    });

    test('derives the controller public key', () {
      expect(toHex(exchange.publicKey),
          'f2b6940243aba536a66e19fb9a39e37f1e76a1cd50ab59b3e05313b4fc93975e');
    });

    test('derives the long-term key', () {
      expect(toHex(exchange.longTermKey), '341e16d13f1cbf73b19d1c2964fee02b');
    });

    test('derives both confirmation values', () {
      expect(toHex(exchange.controllerConfirmation),
          '5fc3b4da865e838ceaf1e9e8bb85d1ac');
      expect(toHex(exchange.podConfirmation), 'af4f10db5f96e5d9cd6cfc1f54f4a92f');
    });

    test('accepts the confirmation the pod actually sent', () {
      exchange.verifyPodConfirmation(hex('af4f10db5f96e5d9cd6cfc1f54f4a92f'));
    });

    test('aborts pairing when the pod confirmation does not match', () {
      expect(
        () => exchange.verifyPodConfirmation(hex('af4f10db5f96e5d9cd6cfc1f54f4a92e')),
        throwsA(isA<PodPairingException>()),
      );
    });

    test('rejects a pod offer of the wrong size', () {
      final fresh = PodKeyExchange.generate();
      expect(() => fresh.acceptPodOffer(hex('0011')),
          throwsA(isA<PodPairingException>()));
    });

    test('two generated exchanges do not share key material', () {
      final first = PodKeyExchange.generate();
      final second = PodKeyExchange.generate();
      expect(toHex(first.privateKey), isNot(toHex(second.privateKey)));
      expect(toHex(first.controllerNonce), isNot(toHex(second.controllerNonce)));
    });
  });
}
