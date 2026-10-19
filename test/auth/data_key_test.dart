import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/auth/data_key/data_key.dart';
import 'package:insulink/src/auth/data_key/data_key_envelope.dart';
import 'package:pointycastle/export.dart';

/// The data key that seals the pod key on the account, and the envelope that
/// wraps it with the password. The vectors were made with Python's hashlib and
/// `cryptography`, independent of this code; the web panel checks the same ones
/// (`src/lib/data-key.check.ts`), so app and panel provably speak one format.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const password = 'correct horse battery staple';
  const envelopeVector =
      '{"version": 1, "kdf": "pbkdf2-sha256", "iterations": 1000, '
      '"salt": "AAECAwQFBgcICQoLDA0ODw==", "nonce": "ZGVmZ2hpamtsbW5v", '
      '"wrapped": "xbDBzZReIQAxvn9wzUW+/0d2Bclb/HMMoCUlyDyJndiEwIAOxxucOYX1DQ2AmfJ/"}';
  final vectorKey = DataKey(Uint8List.fromList(List<int>.generate(32, (i) => 32 + i)));
  final podKey = Uint8List.fromList(List<int>.filled(16, 7));

  /// Stands in for the platform's PBKDF2 with PointyCastle's, which is slow but
  /// the same function.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('insulink/password_key'),
            (call) async {
      final args = call.arguments as Map;
      return (PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
            ..init(Pbkdf2Parameters(
                args['salt'] as Uint8List, args['iterations'] as int, 32)))
          .process(Uint8List.fromList(utf8.encode(args['password'] as String)));
    });
  });

  group('a sealed secret', () {
    test('opens again with the same key', () {
      final sealed = vectorKey.seal(podKey);
      expect(vectorKey.open(sealed), podKey);
    });

    test('matches the independently made vector byte for byte', () {
      expect(vectorKey.seal(podKey),
          'v1.W4MeIE6Fo7c8PBmVHl91yoX5bgMdtJIZrvEjkmig/KXhQk8d6kQSSR7D5Vo=');
    });

    /// The sync only uploads when the blob changed; a random nonce would make
    /// every sync a change.
    test('seals the same secret to the same text every time', () {
      expect(vectorKey.seal(podKey), vectorKey.seal(podKey));
    });

    test('does not open with another key', () {
      final sealed = vectorKey.seal(podKey);
      expect(DataKey.generate().open(sealed), isNull);
    });

    test('a plain value is not mistaken for a sealed one', () {
      expect(vectorKey.open(base64Encode(podKey)), isNull);
    });
  });

  group('the password envelope', () {
    test('unwraps the independently made vector', () async {
      final key = await const DataKeyEnvelope().unwrap(envelopeVector, password);
      expect(key?.bytes, vectorKey.bytes);
    });

    test('refuses a wrong password', () async {
      expect(await const DataKeyEnvelope().unwrap(envelopeVector, 'wrong one'),
          isNull);
    });

    test('refuses an envelope it does not understand', () async {
      expect(await const DataKeyEnvelope().unwrap('{"version": 2}', password),
          isNull);
      expect(await const DataKeyEnvelope().unwrap('not json', password), isNull);
    });

    test('wraps a key so it unwraps with the same password only', () async {
      const envelopes = DataKeyEnvelope(iterations: 1000);
      final key = DataKey.generate();
      final envelope = await envelopes.wrap(key, password);
      expect((await envelopes.unwrap(envelope, password))?.bytes, key.bytes);
      expect(await envelopes.unwrap(envelope, 'other password'), isNull);
      expect(jsonDecode(envelope)['iterations'], 1000);
    });

    test('a new envelope uses the full iteration count by default', () {
      expect(const DataKeyEnvelope().iterations, 600000);
    });
  });
}
