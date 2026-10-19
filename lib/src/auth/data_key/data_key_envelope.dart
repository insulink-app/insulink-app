import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:insulink/src/auth/data_key/data_key.dart';
import 'package:pointycastle/export.dart';

/// The [DataKey] as the backend keeps it: encrypted with a key derived from the
/// account password, so only someone who knows the password can unwrap it. The
/// web panel builds the same envelope with WebCrypto when the password changes
/// there, so every field here is part of a contract with it.
///
/// ```json
/// {"version": 1, "kdf": "pbkdf2-sha256", "iterations": 600000,
///  "salt": "<16 bytes>", "nonce": "<12 bytes>", "wrapped": "<48 bytes>"}
/// ```
/// Bytes are base64; `wrapped` is AES-256-GCM ciphertext plus its 16-byte tag.
class DataKeyEnvelope {
  const DataKeyEnvelope({
    this.derivation = const PasswordKeyDerivation(),
    this.iterations = defaultIterations,
  });

  /// OWASP's floor for PBKDF2-HMAC-SHA256.
  static const int defaultIterations = 600000;
  /// An envelope asking for more is refused rather than left to hang sign-in.
  static const int _maximumIterations = 5000000;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;

  final PasswordKeyDerivation derivation;

  /// What a new envelope is made with; unwrapping reads the count it carries.
  final int iterations;

  Future<String> wrap(DataKey key, String password) async {
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final wrapping = await derivation.derive(password, salt, iterations);
    return jsonEncode({
      'version': 1,
      'kdf': 'pbkdf2-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'wrapped': base64Encode(_cipher(true, wrapping, nonce).process(key.bytes)),
    });
  }

  /// The key inside [envelope], or null for a wrong password or an envelope
  /// this version does not understand.
  Future<DataKey?> unwrap(String envelope, String password) async {
    try {
      final fields = jsonDecode(envelope) as Map<String, dynamic>;
      if (fields['version'] != 1 ||
          fields['kdf'] != 'pbkdf2-sha256' ||
          (fields['iterations'] as int) > _maximumIterations) {
        return null;
      }
      final wrapping = await derivation.derive(password,
          base64Decode(fields['salt'] as String), fields['iterations'] as int);
      final nonce = base64Decode(fields['nonce'] as String);
      final wrapped = base64Decode(fields['wrapped'] as String);
      return DataKey(_cipher(false, wrapping, nonce).process(wrapped));
    } on InvalidCipherTextException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  GCMBlockCipher _cipher(bool forEncryption, Uint8List key, Uint8List nonce) {
    return GCMBlockCipher(AESEngine())
      ..init(forEncryption, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => random.nextInt(256)));
  }
}

/// PBKDF2-HMAC-SHA256 of the password into a 256-bit key, computed by the
/// platform (`PasswordKeyPlugin.kt`): at [DataKeyEnvelope.defaultIterations] a Dart
/// implementation takes many seconds on a phone, the platform's well under one.
class PasswordKeyDerivation {
  const PasswordKeyDerivation();

  static const _channel = MethodChannel('insulink/password_key');

  Future<Uint8List> derive(String password, Uint8List salt, int iterations) async {
    final key = await _channel.invokeMethod<Uint8List>('derive', {
      'password': password,
      'salt': salt,
      'iterations': iterations,
    });
    return key!;
  }
}
