import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

/// The account's data key: 32 random bytes that seal the secrets mirrored to
/// the backend, the pod's long-term key and the G7 session key, so a copy of
/// the database or a stolen session hands out no key to a pod on someone's
/// body. The backend only holds it wrapped with the password
/// ([DataKeyEnvelope]); see docs/POD_KEY_ENCRYPTION.md.
class DataKey {
  const DataKey(this.bytes);

  factory DataKey.generate() {
    final random = Random.secure();
    return DataKey(
      Uint8List.fromList(List<int>.generate(keyLength, (_) => random.nextInt(256))),
    );
  }

  static const int keyLength = 32;
  static const int _nonceLength = 12;
  static const int _tagBits = 128;

  /// Marks a sealed value, so a reader tells it apart from a plain one and a
  /// later format can live next to this one.
  static const String _prefix = 'v1.';

  final Uint8List bytes;

  /// Seals [plaintext] with AES-256-GCM. The nonce is derived from the
  /// plaintext, so the same secret always seals to the same text: the sync
  /// compares the blob with what the backend last accepted, and a random nonce
  /// would make every sync look like a change. Equal output for equal input is
  /// all this gives away, and each secret is sealed on its own.
  String seal(Uint8List plaintext) {
    final nonce = _nonceFor(plaintext);
    final sealed = _cipher(true, nonce).process(plaintext);
    return _prefix + base64Encode([...nonce, ...sealed]);
  }

  /// The plaintext of a [seal]ed value, or null when it is not one or was not
  /// sealed with this key.
  Uint8List? open(String sealed) {
    if (!sealed.startsWith(_prefix)) {
      return null;
    }
    try {
      final raw = base64Decode(sealed.substring(_prefix.length));
      final nonce = Uint8List.sublistView(raw, 0, _nonceLength);
      return _cipher(false, nonce).process(Uint8List.sublistView(raw, _nonceLength));
    } on InvalidCipherTextException {
      return null;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  Uint8List _nonceFor(Uint8List plaintext) {
    final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(bytes));
    return Uint8List.sublistView(mac.process(plaintext), 0, _nonceLength);
  }

  GCMBlockCipher _cipher(bool forEncryption, Uint8List nonce) {
    return GCMBlockCipher(AESEngine())
      ..init(
        forEncryption,
        AEADParameters(KeyParameter(bytes), _tagBits, nonce, Uint8List(0)),
      );
  }
}

/// Where this device keeps the account's [DataKey].
///
/// A key is only ever saved here once the backend holds it wrapped for the
/// current password ([DataKeySync]). Secrets are sealed only while a key is
/// saved, so nothing reaches the account sealed with a key a reinstalled app
/// could not get back.
class DataKeyStore {
  const DataKeyStore([this._storage = const FlutterSecureStorage()]);

  /// Under no prefix a sign-out keeps, so the next account never seals with it.
  static const String storageKey = 'account.data_key';

  final FlutterSecureStorage _storage;

  Future<DataKey?> load() async {
    final stored = await _storage.read(key: storageKey);
    return stored == null ? null : DataKey(base64Decode(stored));
  }

  Future<void> save(DataKey key) =>
      _storage.write(key: storageKey, value: base64Encode(key.bytes));

  Future<void> forget() => _storage.delete(key: storageKey);
}
